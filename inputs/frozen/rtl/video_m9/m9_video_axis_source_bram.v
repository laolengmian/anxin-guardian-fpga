`timescale 1ns/1ps

// M9 private cycle-compatible replacement for video_axis_source_4bank.
// A registered show-ahead head and a continuously scheduled synchronous
// prefetch remove the asynchronous 256x24 memory read while preserving the
// original queue depth, backpressure margin, fallback and output cycle.
module m9_video_axis_source_bram #(
    parameter integer PIXELS_PER_FRAME = 921600,
    parameter integer H_ACT = 1280,
    parameter integer DEPTH = 256,
    parameter [23:0] FALLBACK_RGB = 24'h000000
) (
    input wire video_clk,input wire rst_n,
    input wire frame_start,input wire de,
    input wire px_valid,input wire [23:0] px_rgb,
    output reg pixel_valid,output reg [23:0] rgb888_out,
    output reg axis_user,output reg axis_last,
    output wire fifo_pause,output reg underflow_sticky,
    output wire [31:0] dbg_px_emitted
);
    localparam CW=8;

    reg [23:0] fifo_mem [0:DEPTH-1]
        /* fehdl force_ram=1, ram_style="bram" */;
    reg [CW-1:0] wr_ptr,rd_ptr;
    reg [CW:0] cnt;
    reg [23:0] head,ram_data,forward_data;
    reg forward_valid;
    wire [23:0] prefetch_data=forward_valid ? forward_data : ram_data;

    function [CW-1:0] next_ptr;
        input [CW-1:0] pointer;
        begin
            next_ptr=(pointer==DEPTH[CW-1:0]-8'd1) ? 8'd0 : pointer+8'd1;
        end
    endfunction

    wire fifo_empty=cnt==9'd0;
    wire fifo_full=cnt>=DEPTH[CW:0]-9'd1;
    wire push_word=rst_n && px_valid && !fifo_full;
    wire pop_word=rst_n && de && !fifo_empty;
    wire [CW-1:0] prefetch_addr=pop_word ? next_ptr(next_ptr(rd_ptr))
                                                    : next_ptr(rd_ptr);
    assign fifo_pause=fifo_full;

    // Keep the RAM read unconditional and independent of the collision mux.
    // A separately registered bypass makes mixed-port write/read behavior
    // irrelevant: a same-address RAM result is never consumed.
    always @(posedge video_clk) begin
        if(push_word)
            fifo_mem[wr_ptr]<=px_rgb;
        ram_data<=fifo_mem[prefetch_addr];
        forward_valid<=push_word && wr_ptr==prefetch_addr;
        forward_data<=px_rgb;
    end

    // Queue accounting is identical to the frozen source. The head bypasses
    // RAM only for an empty enqueue and count-one simultaneous pop/push.
    always @(posedge video_clk or negedge rst_n) begin
        if(!rst_n) begin
            wr_ptr<=8'd0;rd_ptr<=8'd0;cnt<=9'd0;head<=24'd0;
        end else begin
            if(push_word) begin
                wr_ptr<=next_ptr(wr_ptr);
                if(cnt==9'd0)
                    head<=px_rgb;
            end
            if(pop_word) begin
                rd_ptr<=next_ptr(rd_ptr);
                if(cnt==9'd1 && push_word)
                    head<=px_rgb;
                else if(cnt>9'd1)
                    head<=prefetch_data;
            end
            case({push_word,pop_word})
                2'b10:cnt<=cnt+9'd1;
                2'b01:cnt<=cnt-9'd1;
                default:begin end
            endcase
        end
    end

    reg de_d;
    wire de_rise=de && !de_d;
    reg user_pending;
    reg [10:0] x_cnt;
    reg [31:0] emit_cnt;

    always @(posedge video_clk or negedge rst_n) begin
        if(!rst_n) begin
            de_d<=1'b0;pixel_valid<=1'b0;rgb888_out<=24'd0;
            axis_user<=1'b0;axis_last<=1'b0;user_pending<=1'b0;
            x_cnt<=11'd0;emit_cnt<=32'd0;underflow_sticky<=1'b0;
        end else begin
            de_d<=de;
            if(frame_start) begin
                user_pending<=1'b1;
                underflow_sticky<=1'b0;
                emit_cnt<=32'd0;
            end
            pixel_valid<=de;
            if(de) begin
                rgb888_out<=fifo_empty ? FALLBACK_RGB : head;
                if(fifo_empty)
                    underflow_sticky<=1'b1;
            end
            axis_user<=1'b0;
            if(de_rise) begin
                axis_user<=user_pending || frame_start;
                user_pending<=1'b0;
            end
            axis_last<=1'b0;
            if(de) begin
                axis_last<=de_rise ? 1'b0 : (x_cnt==H_ACT[10:0]-11'd1);
                x_cnt<=de_rise ? 11'd1 :
                       ((x_cnt==H_ACT[10:0]-11'd1) ? 11'd0 : x_cnt+11'd1);
            end else begin
                x_cnt<=11'd0;
            end
            if(!frame_start && de)
                emit_cnt<=emit_cnt+32'd1;
        end
    end

    assign dbg_px_emitted=emit_cnt;
endmodule
