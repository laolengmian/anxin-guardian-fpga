`timescale 1ns/1ps

// M9 private image loader. One streaming scan exports both BMP and WAV
// catalogs while the board-tested frame-loader write protocol stays unchanged.
module m9_media_loader #(
    parameter integer SOURCE_WIDTH = 640,
    parameter integer SOURCE_HEIGHT = 480,
    parameter integer OUTPUT_WIDTH = 1280,
    parameter integer OUTPUT_HEIGHT = 720,
    parameter integer SIDE_MARGIN = 160,
    parameter integer MAX_SOURCE_WIDTH = 1280,
    parameter integer PROFILE1_WIDTH = 800,
    parameter integer PROFILE1_HEIGHT = 600,
    parameter integer PROFILE1_SCALED_WIDTH = 960,
    parameter integer PROFILE1_SCALED_HEIGHT = 720,
    parameter integer PROFILE1_X_OFFSET = 160,
    parameter integer PROFILE2_WIDTH = 1024,
    parameter integer PROFILE2_HEIGHT = 576,
    parameter integer PROFILE2_SCALED_WIDTH = 1280,
    parameter integer PROFILE2_SCALED_HEIGHT = 720,
    parameter integer PROFILE2_X_OFFSET = 0,
    parameter integer PROFILE3_WIDTH = 1280,
    parameter integer PROFILE3_HEIGHT = 720,
    parameter integer PROFILE3_SCALED_WIDTH = 1280,
    parameter integer PROFILE3_SCALED_HEIGHT = 720,
    parameter integer PROFILE3_X_OFFSET = 0,
    parameter integer MAX_BMP_PIXEL_OFFSET = 4096,
    parameter integer MAX_BMP_TRAILING_BYTES = 4096,
    parameter integer MAX_ROOT_CLUSTERS = 8192,
    parameter integer MAX_FILE_CLUSTERS = 8192
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,
    output wire        busy,
    output reg         done,
    output reg         error,
    output reg  [2:0]  error_stage,
    output reg  [7:0]  error_code,
    output reg  [3:0]  image_complete,
    output reg         catalog_valid,
    output reg  [1:0]  current_image,
    output wire [3:0]  audio_catalog_valid,
    output wire [7:0]  audio_catalog_error,
    output wire [7:0]  catalog_sectors_per_cluster,
    output wire [31:0] catalog_fat_start_lba,
    output wire [31:0] catalog_data_start_lba,
    output wire [31:0] catalog_max_cluster,
    input wire [1:0] audio_catalog_index,
    output wire [31:0] audio_catalog_size,

    input wire audio_file_enable,input wire audio_file_start,
    input wire audio_file_reset,output wire audio_file_busy,
    output wire audio_file_done,output wire audio_file_valid,
    output wire [7:0] audio_file_byte,
    output wire [31:0] audio_file_byte_offset,
    output wire [7:0] audio_file_error,input wire audio_file_ready,

    output wire        reader_req,
    output wire [31:0] reader_lba,
    input  wire        reader_busy,
    input  wire        reader_valid,
    input  wire [7:0]  reader_byte,
    input  wire [8:0]  reader_byte_index,
    input  wire        reader_done,
    input  wire [7:0]  reader_error,

    output reg         load_start,
    output wire [1:0]  load_bank_index,
    input  wire        load_complete,
    input  wire        load_error,
    input  wire [7:0]  load_error_code,
    input  wire        pix_req,
    output wire        pix_valid,
    output wire [23:0] pix_rgb888
);
    localparam [2:0] ERR_STAGE_NONE   = 3'd0;
    localparam [2:0] ERR_STAGE_SCAN   = 3'd1;
    localparam [2:0] ERR_STAGE_FILE   = 3'd2;
    localparam [2:0] ERR_STAGE_BMP    = 3'd3;
    localparam [2:0] ERR_STAGE_LOADER = 3'd4;

    localparam [2:0] ST_IDLE        = 3'd0;
    localparam [2:0] ST_SCAN_START  = 3'd1;
    localparam [2:0] ST_SCAN_WAIT   = 3'd2;
    localparam [2:0] ST_IMAGE_START = 3'd3;
    localparam [2:0] ST_IMAGE_WAIT  = 3'd4;
    localparam [2:0] ST_COMPLETE    = 3'd5;
    localparam [2:0] ST_ERROR       = 3'd6;
    localparam [2:0] ST_IMAGE_SELECT = 3'd7;

    reg [2:0] state;
    reg scan_start;
    reg file_start;
    reg bmp_start;
    reg bmp_done_seen;
    reg loader_done_seen;
    reg pipeline_reset;

    wire scan_busy;
    wire scan_done;
    wire [7:0] scan_fs_error;
    wire [7:0] image_catalog_error;
    wire [7:0] scan_error = scan_fs_error != 0 ?
                            scan_fs_error : image_catalog_error;
    wire [7:0] sectors_per_cluster;
    wire [31:0] fat_start_lba;
    wire [31:0] data_start_lba;
    wire [31:0] max_cluster;
    wire [3:0] resource_valid;
    wire catalog_entry_valid;
    wire [31:0] selected_cluster;
    wire [31:0] selected_size;
    reg [31:0] selected_cluster_q,selected_size_q;
    assign catalog_sectors_per_cluster=sectors_per_cluster;
    assign catalog_fat_start_lba=fat_start_lba;
    assign catalog_data_start_lba=data_start_lba;
    assign catalog_max_cluster=max_cluster;

    wire scan_sector_req;
    wire [31:0] scan_sector_lba;
    wire scan_sector_ready;
    wire file_sector_req;
    wire [31:0] file_sector_lba;
    wire file_sector_ready;

    wire replay_sector_req;
    wire [31:0] replay_sector_lba;
    wire replay_sector_busy;
    wire replay_sector_valid;
    wire [7:0] replay_sector_byte;
    wire [8:0] replay_sector_byte_index;
    wire replay_sector_done;
    wire [7:0] replay_sector_error;
    wire replay_sector_ready;

    wire file_busy;
    wire file_done;
    wire file_valid;
    wire [7:0] file_byte;
    wire [31:0] file_byte_offset;
    wire stream_file_ready;
    wire image_file_ready;
    wire file_ready=stream_file_ready;
    wire [7:0] file_error;

    wire bmp_done;
    wire bmp_error;
    wire [7:0] bmp_error_code;
    wire header_accepted;

    wire scan_owner = state == ST_SCAN_START || state == ST_SCAN_WAIT;
    wire audio_service_enabled = audio_file_enable && catalog_valid && state==ST_IDLE;
    wire worker_rst_n = rst_n && !pipeline_reset &&
                        !(audio_service_enabled && audio_file_reset);

    assign busy = state != ST_IDLE;
    assign load_bank_index = current_image;
    assign replay_sector_req = scan_owner ? scan_sector_req : file_sector_req;
    assign replay_sector_lba = scan_owner ? scan_sector_lba : file_sector_lba;
    assign replay_sector_ready = scan_owner ? scan_sector_ready : file_sector_ready;
    assign stream_file_ready=audio_service_enabled ? audio_file_ready : image_file_ready;
    assign audio_file_busy=audio_service_enabled &&
                           (file_busy || replay_sector_busy || file_sector_req);
    assign audio_file_done=audio_service_enabled && file_done;
    assign audio_file_valid=audio_service_enabled && file_valid;
    assign audio_file_byte=file_byte;
    assign audio_file_byte_offset=file_byte_offset;
    assign audio_file_error=audio_service_enabled ? file_error : 8'd0;
    assign audio_catalog_size=selected_size_q;

    sd_sector_replay_buffer_ready u_sector_replay (
        .clk(clk), .rst_n(worker_rst_n),
        .sector_req(replay_sector_req), .sector_lba(replay_sector_lba),
        .sector_busy(replay_sector_busy), .sector_valid(replay_sector_valid),
        .sector_byte(replay_sector_byte),
        .sector_byte_index(replay_sector_byte_index),
        .sector_done(replay_sector_done), .sector_error(replay_sector_error),
        .sector_ready(replay_sector_ready),
        .reader_req(reader_req), .reader_lba(reader_lba),
        .reader_busy(reader_busy), .reader_valid(reader_valid),
        .reader_byte(reader_byte), .reader_byte_index(reader_byte_index),
        .reader_done(reader_done), .reader_error(reader_error)
    );

    m9_fat32_media_catalog #(
        .MAX_ROOT_CLUSTERS(MAX_ROOT_CLUSTERS)
    ) u_scanner (
        .clk(clk),.rst_n(rst_n),.scan_start(scan_start),
        .scan_busy(scan_busy),.scan_done(scan_done),.fs_error(scan_fs_error),
        .image_catalog_error(image_catalog_error),
        .audio_catalog_error(audio_catalog_error),.partition_lba(),
        .sectors_per_cluster(sectors_per_cluster),.fat_start_lba(fat_start_lba),
        .data_start_lba(data_start_lba),.max_cluster(max_cluster),
        .image_valid(resource_valid),.audio_valid(audio_catalog_valid),
        .catalog_select_audio(audio_service_enabled),
        .catalog_select_index(audio_service_enabled ? audio_catalog_index : current_image),
        .catalog_entry_valid(catalog_entry_valid),
        .catalog_entry_cluster(selected_cluster),
        .catalog_entry_size(selected_size),
        .sector_req(scan_sector_req),.sector_lba(scan_sector_lba),
        .sector_busy(replay_sector_busy),
        .sector_valid(replay_sector_valid),
        .sector_byte(replay_sector_byte),.sector_byte_index(replay_sector_byte_index),
        .sector_done(replay_sector_done),
        .sector_error(replay_sector_error),.sector_ready(scan_sector_ready)
    );

    m9_fat32_file_streamer #(
        .MAX_VISITED_CLUSTERS(MAX_FILE_CLUSTERS)
    ) u_file_streamer (
        .clk(clk), .rst_n(worker_rst_n),
        .file_start(audio_service_enabled ? audio_file_start : file_start),
        .first_cluster(selected_cluster_q),.file_size(selected_size_q),
        .sectors_per_cluster(sectors_per_cluster),
        .fat_start_lba(fat_start_lba), .data_start_lba(data_start_lba),
        .max_cluster(max_cluster), .file_busy(file_busy),
        .file_done(file_done), .file_valid(file_valid), .file_byte(file_byte),
        .file_byte_offset(file_byte_offset), .file_ready(stream_file_ready),
        .fs_error(file_error), .sector_req(file_sector_req),
        .sector_lba(file_sector_lba),
        .sector_busy(replay_sector_busy),
        .sector_valid(replay_sector_valid),
        .sector_byte(replay_sector_byte),
        .sector_byte_index(replay_sector_byte_index),
        .sector_done(replay_sector_done),
        .sector_error(replay_sector_error), .sector_ready(file_sector_ready)
    );

    m9_bmp24_720p_pixel_source #(
        .SOURCE_WIDTH(SOURCE_WIDTH), .SOURCE_HEIGHT(SOURCE_HEIGHT),
        .OUTPUT_WIDTH(OUTPUT_WIDTH), .OUTPUT_HEIGHT(OUTPUT_HEIGHT),
        .SIDE_MARGIN(SIDE_MARGIN), .MAX_SOURCE_WIDTH(MAX_SOURCE_WIDTH),
        .PROFILE1_WIDTH(PROFILE1_WIDTH),
        .PROFILE1_HEIGHT(PROFILE1_HEIGHT),
        .PROFILE1_SCALED_WIDTH(PROFILE1_SCALED_WIDTH),
        .PROFILE1_SCALED_HEIGHT(PROFILE1_SCALED_HEIGHT),
        .PROFILE1_X_OFFSET(PROFILE1_X_OFFSET),
        .PROFILE2_WIDTH(PROFILE2_WIDTH),
        .PROFILE2_HEIGHT(PROFILE2_HEIGHT),
        .PROFILE2_SCALED_WIDTH(PROFILE2_SCALED_WIDTH),
        .PROFILE2_SCALED_HEIGHT(PROFILE2_SCALED_HEIGHT),
        .PROFILE2_X_OFFSET(PROFILE2_X_OFFSET),
        .PROFILE3_WIDTH(PROFILE3_WIDTH),
        .PROFILE3_HEIGHT(PROFILE3_HEIGHT),
        .PROFILE3_SCALED_WIDTH(PROFILE3_SCALED_WIDTH),
        .PROFILE3_SCALED_HEIGHT(PROFILE3_SCALED_HEIGHT),
        .PROFILE3_X_OFFSET(PROFILE3_X_OFFSET),
        .MAX_BMP_PIXEL_OFFSET(MAX_BMP_PIXEL_OFFSET),
        .MAX_BMP_TRAILING_BYTES(MAX_BMP_TRAILING_BYTES)
    ) u_bmp_source (
        .clk(clk), .rst_n(worker_rst_n), .start(bmp_start),
        .file_size(selected_size_q), .file_valid(file_valid),
        .file_byte(file_byte), .file_byte_offset(file_byte_offset),
        .file_done(file_done), .upstream_error(file_error),
        .file_ready(image_file_ready), .pix_req(pix_req), .abort(1'b0),
        .pix_valid(pix_valid), .pix_rgb888(pix_rgb888),
        .bmp_done(bmp_done), .bmp_error(bmp_error),
        .error_code(bmp_error_code), .header_accepted(header_accepted)
    );

    task enter_error;
        input [2:0] stage_value;
        input [7:0] code_value;
        begin
            error <= 1'b1;
            error_stage <= stage_value;
            error_code <= code_value;
            pipeline_reset <= 1'b1;
            state <= ST_ERROR;
        end
    endtask

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ST_IDLE;
            scan_start <= 1'b0;
            file_start <= 1'b0;
            bmp_start <= 1'b0;
            load_start <= 1'b0;
            done <= 1'b0;
            error <= 1'b0;
            error_stage <= ERR_STAGE_NONE;
            error_code <= 8'd0;
            image_complete <= 4'd0;
            catalog_valid <= 1'b0;
            current_image <= 2'd0;
            bmp_done_seen <= 1'b0;
            loader_done_seen <= 1'b0;
            pipeline_reset <= 1'b0;
            selected_cluster_q <= 32'd0;
            selected_size_q <= 32'd0;
        end else begin
            scan_start <= 1'b0;
            file_start <= 1'b0;
            bmp_start <= 1'b0;
            load_start <= 1'b0;
            done <= 1'b0;
            if(audio_service_enabled) begin
                selected_cluster_q<=selected_cluster;
                selected_size_q<=selected_size;
            end

            case (state)
                ST_IDLE: begin
                    if (start) begin
                        error <= 1'b0;
                        error_stage <= ERR_STAGE_NONE;
                        error_code <= 8'd0;
                        image_complete <= 4'd0;
                        catalog_valid <= 1'b0;
                        current_image <= 2'd0;
                        pipeline_reset <= 1'b0;
                        state <= ST_SCAN_START;
                    end
                end

                ST_SCAN_START: begin
                    scan_start <= 1'b1;
                    state <= ST_SCAN_WAIT;
                end

                ST_SCAN_WAIT: begin
                    if (scan_done) begin
                        if (scan_error != 0)
                            enter_error(ERR_STAGE_SCAN, scan_error);
                        else if (resource_valid != 4'hf)
                            enter_error(ERR_STAGE_SCAN, 8'h22);
                        else begin
                            catalog_valid <= 1'b1;
                            current_image <= 2'd0;
                            state <= ST_IMAGE_SELECT;
                        end
                    end
                end

                ST_IMAGE_SELECT:state <= ST_IMAGE_START;

                ST_IMAGE_START: begin
                    selected_cluster_q<=selected_cluster;
                    selected_size_q<=selected_size;
                    file_start <= 1'b1;
                    bmp_start <= 1'b1;
                    load_start <= 1'b1;
                    bmp_done_seen <= 1'b0;
                    loader_done_seen <= 1'b0;
                    state <= ST_IMAGE_WAIT;
                end

                ST_IMAGE_WAIT: begin
                    if (load_error) begin
                        enter_error(ERR_STAGE_LOADER, load_error_code);
                    end else if (file_done && file_error != 0) begin
                        enter_error(ERR_STAGE_FILE, file_error);
                    end else if (bmp_error) begin
                        enter_error(ERR_STAGE_BMP, bmp_error_code);
                    end else begin
                        if (bmp_done)
                            bmp_done_seen <= 1'b1;
                        if (load_complete)
                            loader_done_seen <= 1'b1;
                        if ((bmp_done_seen || bmp_done) &&
                            (loader_done_seen || load_complete)) begin
                            image_complete[current_image] <= 1'b1;
                            if (current_image == 2'd3)
                                state <= ST_COMPLETE;
                            else begin
                                current_image <= current_image + 1'b1;
                                state <= ST_IMAGE_SELECT;
                            end
                        end
                    end
                end

                ST_COMPLETE: begin
                    done <= 1'b1;
                    state <= ST_IDLE;
                end

                ST_ERROR: begin
                    error <= 1'b1;
                    pipeline_reset <= 1'b1;
                end

                default: state <= ST_IDLE;
            endcase
        end
    end
endmodule
