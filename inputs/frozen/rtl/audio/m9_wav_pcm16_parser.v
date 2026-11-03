// M9: preserve the frozen parser cycle contract; precheck the next chunk
// during the existing byte-capture slot, before error-code/state selection.
// Consume only valid&&ready, keep PCM stable under backpressure. No CDC here.
// The first data chunk is played; remaining file bytes are drained, not audio.
module m9_wav_pcm16_parser (
    input wire clk, input wire rst_n, input wire start, input wire abort,
    input wire [31:0] file_size,
    input wire file_valid, output wire file_ready,
    input wire [7:0] file_byte, input wire [31:0] file_byte_offset,
    input wire file_done, input wire [7:0] upstream_error,
    output reg pcm_valid, input wire pcm_ready,
    output reg signed [15:0] pcm_data, output reg pcm_last,
    output wire busy, output reg done, output reg error,
    output reg [7:0] error_code, output reg header_accepted,
    output reg [31:0] sample_count
);
    localparam IDLE=0, RIFF=1, NEXT_CHUNK=2, CHUNK=3, CHECK=4,
               FMT=5, SKIP=6, DATA=7, DRAIN=8, CHUNK_END=9, CHUNK_PAD=10;
    localparam [7:0] ERR_SIZE=1, ERR_SIGNATURE=2, ERR_CHUNK=3,
                     ERR_FORMAT=4, ERR_OFFSET=5, ERR_EOF=6,
                     ERR_TRANSPORT=7, ERR_DATA=8;
    reg [3:0] state;
    reg [31:0] size_r,position,riff_end,shift,chunk_id,chunk_size,remaining;
    reg [4:0] byte_index;
    reg fmt_seen,eof_seen,odd_pad,low_pending;
    reg [7:0] low_byte;
    reg byte_pending,byte_offset_error,byte_reaches_end,at_file_end;
    reg [7:0] byte_q;
    reg next_chunk_bounds_error;
    wire [31:0] next_position=position+32'd1;
    wire [31:0] assembled={byte_q,shift[31:8]};
    reg [32:0] chunk_end;
    assign busy=state!=IDLE;
    assign file_ready=rst_n && !abort && !byte_pending && !at_file_end &&
        (state==RIFF || state==CHUNK || state==FMT || state==SKIP ||
         state==DRAIN || (state==DATA && (!pcm_valid || pcm_ready)));
    wire take=byte_pending;

    // One byte in flight. The state and position stay fixed during capture;
    // DATA reserves its PCM output slot before accepting either byte.
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            byte_pending<=0;byte_q<=0;byte_offset_error<=0;byte_reaches_end<=0;
            next_chunk_bounds_error<=0;
        end else if(abort || !busy) byte_pending<=0;
        else begin
            byte_pending<=file_valid && file_ready;
            if(file_valid && file_ready) begin
                byte_q<=file_byte;
                byte_offset_error<=file_byte_offset!=position;
                byte_reaches_end<=next_position==size_r;
                // A taken byte advances position once before NEXT_CHUNK.
                // Every entry to NEXT_CHUNK follows such a capture, even
                // after zero-sized chunks; no file byte is accepted at 2^32-1.
                next_chunk_bounds_error<={1'b0,position}+33'd9>{1'b0,riff_end};
            end
        end
    end

    // Expected first 16 fmt bytes: tag1/mono/48000/96000/align2/16bit.
    function [7:0] fmt_byte;
        input [4:0] index;
        begin
            case(index)
                0,2,10: fmt_byte=8'h01;
                4: fmt_byte=8'h80;
                5: fmt_byte=8'hbb;
                9: fmt_byte=8'h77;
                12: fmt_byte=8'h02;
                14: fmt_byte=8'h10;
                default: fmt_byte=8'h00;
            endcase
        end
    endfunction
    task fail;
        input [7:0] code;
        begin
            state<=IDLE;error<=1;error_code<=code;pcm_valid<=0;
        end
    endtask

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state<=IDLE;at_file_end<=0;size_r<=0;position<=0;riff_end<=0;shift<=0;
            chunk_id<=0;chunk_size<=0;remaining<=0;byte_index<=0;chunk_end<=0;
            fmt_seen<=0;eof_seen<=0;odd_pad<=0;low_pending<=0;low_byte<=0;
            pcm_valid<=0;pcm_data<=0;pcm_last<=0;done<=0;error<=0;
            error_code<=0;header_accepted<=0;sample_count<=0;
        end else begin
            done<=0;
            if(pcm_valid && pcm_ready) pcm_valid<=0;
            if(abort) begin
                state<=IDLE;pcm_valid<=0;error<=0;error_code<=0;
                header_accepted<=0;sample_count<=0;
            end else if(start && !busy) begin
                size_r<=file_size;position<=0;at_file_end<=0;riff_end<=0;shift<=0;
                byte_index<=0;fmt_seen<=0;eof_seen<=0;low_pending<=0;
                pcm_valid<=0;pcm_last<=0;error<=0;error_code<=0;
                header_accepted<=0;sample_count<=0;
                if(file_size<44) fail(ERR_SIZE); else state<=RIFF;
            end else if(busy) begin
                if(file_done) eof_seen<=1;
                if(upstream_error!=0) fail(ERR_TRANSPORT);
                else if((file_done || eof_seen) && !file_valid && !byte_pending && !at_file_end)
                    fail(ERR_EOF);
                else if(file_valid && at_file_end) fail(ERR_SIZE);
                else if(take && byte_offset_error) fail(ERR_OFFSET);
                else begin
                    if(take) begin position<=next_position;at_file_end<=byte_reaches_end;end
                    case(state)
                        RIFF: if(take) begin
                            shift<=assembled;byte_index<=byte_index+1'b1;
                            if(byte_index==3 && assembled!=32'h46464952)
                                fail(ERR_SIGNATURE);
                            else if(byte_index==7) begin
                                if(assembled<4 || {1'b0,assembled}+33'd8>{1'b0,size_r})
                                    fail(ERR_SIZE);
                                else riff_end<=assembled+8;
                            end else if(byte_index==11) begin
                                if(assembled!=32'h45564157) fail(ERR_SIGNATURE);
                                else state<=NEXT_CHUNK;
                            end
                        end
                        NEXT_CHUNK: begin
                            if(next_chunk_bounds_error) fail(ERR_CHUNK);
                            else begin byte_index<=0;shift<=0;state<=CHUNK;end
                        end
                        CHUNK: if(take) begin
                            shift<=assembled;byte_index<=byte_index+1'b1;
                            if(byte_index==3) chunk_id<=assembled;
                            if(byte_index==7) begin chunk_size<=assembled;state<=CHUNK_END;end
                        end
                        // Addition, odd padding and comparison use separate clocks.
                        // The byte source remains stalled throughout these states.
                        CHUNK_END: begin
                            chunk_end<={1'b0,position}+{1'b0,chunk_size};state<=CHUNK_PAD;
                        end
                        CHUNK_PAD: begin
                            chunk_end<=chunk_end+chunk_size[0];state<=CHECK;
                        end
                        CHECK: begin
                            if(chunk_end>{1'b0,riff_end}) fail(ERR_CHUNK);
                            else if(chunk_id==32'h20746d66) begin
                                if(fmt_seen || chunk_size<16) fail(ERR_FORMAT);
                                else begin
                                    byte_index<=0;remaining<=chunk_size;
                                    odd_pad<=chunk_size[0];state<=FMT;
                                end
                            end else if(chunk_id==32'h61746164) begin
                                if(!fmt_seen || chunk_size==0 || chunk_size[0]) fail(ERR_DATA);
                                else begin
                                    header_accepted<=1;sample_count<=chunk_size>>1;
                                    remaining<=chunk_size;low_pending<=0;state<=DATA;
                                end
                            end else if(chunk_size==0) state<=NEXT_CHUNK;
                            else begin remaining<=chunk_size+chunk_size[0];state<=SKIP;end
                        end
                        FMT: if(take) begin
                            remaining<=remaining-1'b1;
                            // Saturate index after the fixed fmt prefix; extensions are skipped.
                            if(byte_index<16) byte_index<=byte_index+1'b1;
                            if(byte_index<16 && byte_q!=fmt_byte(byte_index)) fail(ERR_FORMAT);
                            else if(remaining==1) begin
                                fmt_seen<=1;
                                if(odd_pad) begin remaining<=1;state<=SKIP;end
                                else state<=NEXT_CHUNK;
                            end
                        end
                        SKIP: if(take) begin
                            remaining<=remaining-1'b1;
                            if(remaining==1) state<=NEXT_CHUNK;
                        end
                        DATA: if(take) begin
                            remaining<=remaining-1'b1;
                            low_pending<=!low_pending;
                            if(!low_pending) low_byte<=byte_q;
                            else begin
                                pcm_data<={byte_q,low_byte};pcm_valid<=1;
                                pcm_last<=remaining==1;
                                if(remaining==1) state<=DRAIN;
                            end
                        end
                        DRAIN: if(eof_seen && at_file_end && !pcm_valid) begin
                            done<=1;state<=IDLE;
                        end
                        default: fail(ERR_CHUNK);
                    endcase
                end
            end
        end
    end
endmodule
