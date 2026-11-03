// M9 private read-only audio client. The image phase supplies the shared FAT32
// catalog and file service, so this loader contains only WAV parsing/control.
module m9_audio_loader (
    input wire clk,input wire rst_n,input wire start,
    input wire [1:0] desired_image,input wire replay_request,
    output reg replay_accept,
    input wire [3:0] shared_catalog_valid,input wire [7:0] shared_catalog_error,
    input wire [31:0] catalog_file_size,
    output reg [1:0] current_image,output reg catalog_valid,
    output reg error,output reg [7:0] error_code,
    output reg play_enable,output wire fifo_reset,output wire file_loaded,
    output wire pcm_valid,input wire pcm_ready,
    output wire signed [15:0] pcm_data,output wire pcm_last,
    output reg file_start,output wire file_reset,
    input wire file_service_busy,input wire file_done,input wire file_valid,
    input wire [7:0] file_byte,input wire [31:0] file_byte_offset,
    input wire [7:0] file_error,output wire file_ready
);
    localparam [2:0] ST_IDLE=3'd0,ST_QUIET=3'd1,ST_RELEASE=3'd2;
    localparam [2:0] ST_START_FILE=3'd3,ST_PLAY=3'd4,ST_FAULT=3'd5;
    localparam [7:0] ERR_RESOURCE_MISSING=8'h22;

    reg [2:0] state;
    reg pipeline_reset,wav_start;
    reg [5:0] quiet_count;

    wire worker_rst_n=rst_n && !pipeline_reset;
    assign fifo_reset=!rst_n || pipeline_reset;
    assign file_reset=!worker_rst_n;

    wire wav_error;
    wire [7:0] wav_error_code;
    m9_wav_pcm16_parser u_wav (
        .clk(clk),.rst_n(worker_rst_n),.start(wav_start),.abort(1'b0),
        .file_size(catalog_file_size),.file_valid(file_valid),.file_ready(file_ready),
        .file_byte(file_byte),.file_byte_offset(file_byte_offset),
        .file_done(file_done),.upstream_error(file_error),
        .pcm_valid(pcm_valid),.pcm_ready(pcm_ready),.pcm_data(pcm_data),
        .pcm_last(pcm_last),.busy(),.done(file_loaded),.error(wav_error),
        .error_code(wav_error_code),.header_accepted(),.sample_count()
    );

    task fail;
        input [7:0] code;
        begin
            error<=1'b1;error_code<=code;play_enable<=1'b0;
            pipeline_reset<=1'b1;state<=ST_FAULT;
        end
    endtask

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state<=ST_IDLE;pipeline_reset<=1'b1;file_start<=1'b0;wav_start<=1'b0;
            replay_accept<=1'b0;
            current_image<=2'd0;catalog_valid<=1'b0;error<=1'b0;
            error_code<=8'd0;play_enable<=1'b0;quiet_count<=6'd0;
        end else begin
            file_start<=1'b0;wav_start<=1'b0;replay_accept<=1'b0;
            case(state)
                ST_IDLE:if(start) begin
                    error<=1'b0;error_code<=8'd0;play_enable<=1'b0;
                    if(shared_catalog_error!=0) fail(shared_catalog_error);
                    else if(shared_catalog_valid!=4'hf) fail(ERR_RESOURCE_MISSING);
                    else begin
                        catalog_valid<=1'b1;pipeline_reset<=1'b1;
                        quiet_count<=6'd0;state<=ST_QUIET;
                    end
                end
                ST_QUIET:begin
                    if(file_service_busy) quiet_count<=6'd0;
                    else if(quiet_count==6'd31) begin
                        current_image<=desired_image;pipeline_reset<=1'b0;
                        quiet_count<=6'd0;state<=ST_RELEASE;
                    end else quiet_count<=quiet_count+1'b1;
                end
                ST_RELEASE:begin
                    if(quiet_count==6'd7) state<=ST_START_FILE;
                    else quiet_count<=quiet_count+1'b1;
                end
                ST_START_FILE:begin
                    file_start<=1'b1;wav_start<=1'b1;play_enable<=1'b1;
                    state<=ST_PLAY;
                end
                ST_PLAY:begin
                    if(desired_image!=current_image) begin
                        play_enable<=1'b0;pipeline_reset<=1'b1;
                        quiet_count<=6'd0;state<=ST_QUIET;
                    end else if(wav_error) fail(wav_error_code);
                    else if(file_done && file_error!=0) fail(file_error);
                    else if(replay_request) begin
                        replay_accept<=1'b1;play_enable<=1'b0;pipeline_reset<=1'b1;
                        quiet_count<=6'd0;state<=ST_QUIET;
                    end
                end
                ST_FAULT:if(catalog_valid && desired_image!=current_image) begin
                    error<=1'b0;error_code<=8'd0;quiet_count<=6'd0;
                    state<=ST_QUIET;
                end
                default:fail(8'hff);
            endcase
        end
    end
endmodule
