`timescale 1ns/1ps

// M9 private read-only BMP source. Header fields are captured while bytes
// stream past; the 54-byte distributed register array is intentionally absent.
// Exact geometry profiles drive one shared row-buffered nearest-neighbour scaler.
// file_done is a completion pulse after the final file_valid beat; the integrated
// m9_fat32_file_streamer satisfies this contract through its ST_FINISH state.
module m9_bmp24_720p_pixel_source #(
    parameter integer SOURCE_WIDTH  = 640,
    parameter integer SOURCE_HEIGHT = 480,
    parameter integer OUTPUT_WIDTH  = 1280,
    parameter integer OUTPUT_HEIGHT = 720,
    parameter integer SIDE_MARGIN   = 160,
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
    parameter integer MAX_BMP_TRAILING_BYTES = 4096
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,
    input  wire [31:0] file_size,
    input  wire        file_valid,
    input  wire [7:0]  file_byte,
    input  wire [31:0] file_byte_offset,
    input  wire        file_done,
    input  wire [7:0]  upstream_error,
    output wire        file_ready,
    input  wire        pix_req,
    input  wire        abort,
    output reg         pix_valid,
    output reg  [23:0] pix_rgb888,
    output reg         bmp_done,
    output reg         bmp_error,
    output reg  [7:0]  error_code,
    output reg         header_accepted
);
    localparam [7:0] ERR_SIGNATURE           = 8'h31;
    localparam [7:0] ERR_DIMENSIONS          = 8'h32;
    localparam [7:0] ERR_PLANES              = 8'h33;
    localparam [7:0] ERR_BPP                 = 8'h34;
    localparam [7:0] ERR_COMPRESSION         = 8'h35;
    localparam [7:0] ERR_OFFSET              = 8'h36;
    localparam [7:0] ERR_TRUNCATED           = 8'h37;
    localparam [7:0] ERR_UPSTREAM            = 8'h38;
    localparam [7:0] ERR_ORDER               = 8'h39;
    localparam [7:0] ERR_ABORT               = 8'h3a;
    localparam [7:0] ERR_UNSUPPORTED_PROFILE = 8'h3b;

    localparam [3:0] ST_IDLE     = 4'd0;
    localparam [3:0] ST_HEADER   = 4'd1;
    localparam [3:0] ST_VALIDATE = 4'd2;
    localparam [3:0] ST_BOUNDS   = 4'd3;
    localparam [3:0] ST_SIZE     = 4'd4;
    localparam [3:0] ST_SKIP     = 4'd5;
    localparam [3:0] ST_LOAD_ROW = 4'd6;
    localparam [3:0] ST_PADDING  = 4'd7;
    localparam [3:0] ST_EMIT_ROW = 4'd8;
    localparam [3:0] ST_WAIT_END = 4'd9;
    localparam [3:0] ST_DONE        = 4'd10;
    localparam [3:0] ST_ERROR       = 4'd11;
    localparam [3:0] ST_SIZE_COMMIT = 4'd12;
    localparam [1:0] SIZE_RESULT_OK        = 2'd0;
    localparam [1:0] SIZE_RESULT_OFFSET    = 2'd1;
    localparam [1:0] SIZE_RESULT_TRUNCATED = 2'd2;
    localparam [31:0] MAX_BMP_PIXEL_OFFSET_VALUE = MAX_BMP_PIXEL_OFFSET;
    localparam [32:0] MAX_BMP_TRAILING_BYTES_VALUE = MAX_BMP_TRAILING_BYTES;

    reg [3:0] state;
    reg [31:0] header_file_size_q;
    reg [31:0] header_pixel_offset_q;
    reg [31:0] dib_size_q;
    reg [31:0] image_width_q;
    reg [31:0] image_height_q;
    reg [31:0] image_data_size_q;
    reg signature_matches;
    reg planes_match,bpp_matches,compression_matches;
    reg [23:0] row_mem_1024 [0:1023]
        /* fehdl force_ram=1, ram_style="bram" */;
    reg [23:0] row_mem_256 [0:255]
        /* fehdl force_ram=1, ram_style="bram" */;

    reg [31:0] expected_offset;
    reg [31:0] pixel_offset;
    reg [31:0] required_end;
    reg required_end_overflow;
    reg [31:0] allowed_end;
    reg allowed_end_overflow;
    // Registered copy of the loader's file_size plus a separate profile stage
    // keep the loader mux, profile decode, add and comparisons out of one path.
    reg [31:0] file_size_q;
    reg [31:0] source_data_bytes_q;
    reg [1:0] size_result_q /* fehdl keep="true" */;

    reg [1:0] active_profile_id;
    reg [10:0] active_source_width;
    reg [9:0] active_source_height;
    reg [10:0] active_scaled_width;
    reg [9:0] active_scaled_height;
    reg [10:0] active_x_offset;
    reg [9:0] active_y_offset;
    reg [2:0] active_scale_numerator;
    reg [2:0] active_scale_denominator;
    reg [12:0] active_source_row_bytes;
    reg [12:0] active_source_row_stride;

    reg [9:0] physical_row;
    reg [10:0] source_x;
    reg [12:0] row_byte_pos;
    reg [1:0] channel_phase;
    reg [7:0] blue_hold;
    reg [7:0] green_hold;

    reg [10:0] output_x;
    reg [9:0] output_y;
    reg [10:0] source_emit_x;
    reg [3:0] horizontal_phase;
    reg [3:0] vertical_phase;
    reg [23:0] row_mem_1024_q;
    reg [23:0] row_mem_256_q;
    wire [23:0] row_pixel_hold;
    reg row_pixel_valid;
    reg file_done_seen;
    reg payload_incomplete_q;

    wire decoded_profile_valid;
    wire [1:0] decoded_profile_id;
    wire [10:0] decoded_source_width;
    wire [9:0] decoded_source_height;
    wire [10:0] decoded_scaled_width;
    wire [9:0] decoded_scaled_height;
    wire [10:0] decoded_x_offset;
    wire [9:0] decoded_y_offset;
    wire [2:0] decoded_scale_numerator;
    wire [2:0] decoded_scale_denominator;
    wire [12:0] decoded_source_row_bytes;
    wire [12:0] decoded_source_row_stride;
    wire [31:0] decoded_source_data_bytes;
    wire [11:0] decoded_canvas_width =
        {1'b0,decoded_x_offset} + {1'b0,decoded_scaled_width} +
        {1'b0,decoded_x_offset};
    wire decoded_geometry_valid =
        decoded_source_width != 0 &&
        decoded_source_width <= MAX_SOURCE_WIDTH &&
        decoded_source_height != 0 &&
        decoded_scaled_width != 0 &&
        decoded_scaled_height == OUTPUT_HEIGHT &&
        decoded_y_offset == 0 &&
        decoded_canvas_width == OUTPUT_WIDTH;

    wire [4:0] horizontal_phase_sum =
        {1'b0,horizontal_phase} + {2'b00,active_scale_denominator};
    wire [4:0] vertical_phase_sum =
        {1'b0,vertical_phase} + {2'b00,active_scale_denominator};
    wire accept_file_byte = file_valid && file_ready;
    wire row_mem_write = accept_file_byte &&
                         state == ST_LOAD_ROW &&
                         channel_phase == 2'd2;
    wire [23:0] row_mem_write_data =
        {file_byte,green_hold,blue_hold};

    assign row_pixel_hold = source_emit_x[10] ?
                            row_mem_256_q : row_mem_1024_q;
    assign file_ready = state == ST_HEADER || state == ST_SKIP ||
                        state == ST_LOAD_ROW || state == ST_PADDING ||
                        state == ST_WAIT_END;

    generate
        if (MAX_SOURCE_WIDTH > 1024 + 256) begin : g_invalid_max_source_width
            m9_bmp24_max_source_width_exceeds_1280 u_configuration_error();
        end
    endgenerate

    initial begin
        if (SOURCE_WIDTH < 2 || SOURCE_HEIGHT < 2 ||
            SOURCE_WIDTH[0] || SOURCE_HEIGHT[0] ||
            MAX_SOURCE_WIDTH < SOURCE_WIDTH ||
            MAX_BMP_PIXEL_OFFSET < 54 ||
            MAX_BMP_TRAILING_BYTES < 0 ||
            SOURCE_WIDTH + SOURCE_WIDTH/2 + 2*SIDE_MARGIN != OUTPUT_WIDTH ||
            SOURCE_HEIGHT + SOURCE_HEIGHT/2 != OUTPUT_HEIGHT) begin
            $display("BMP24_720P_CONFIG_ERROR invalid P0 geometry");
            $finish;
        end
    end

    always @(posedge clk) begin
        if (row_mem_write && !source_x[10])
            row_mem_1024[source_x[9:0]] <= row_mem_write_data;
        if (row_mem_write && source_x[10])
            row_mem_256[source_x[7:0]] <= row_mem_write_data;

        row_mem_1024_q <= row_mem_1024[source_emit_x[9:0]];
        row_mem_256_q <= row_mem_256[source_emit_x[7:0]];
    end

    m9_bmp_profile_decoder #(
        .PROFILE0_WIDTH(SOURCE_WIDTH),
        .PROFILE0_HEIGHT(SOURCE_HEIGHT),
        .PROFILE0_SCALED_WIDTH(OUTPUT_WIDTH-2*SIDE_MARGIN),
        .PROFILE0_SCALED_HEIGHT(OUTPUT_HEIGHT),
        .PROFILE0_X_OFFSET(SIDE_MARGIN),
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
        .PROFILE3_X_OFFSET(PROFILE3_X_OFFSET)
    ) u_profile_decoder (
        .image_width(image_width_q),
        .image_height(image_height_q),
        .profile_valid(decoded_profile_valid),
        .profile_id(decoded_profile_id),
        .source_width(decoded_source_width),
        .source_height(decoded_source_height),
        .scaled_width(decoded_scaled_width),
        .scaled_height(decoded_scaled_height),
        .x_offset(decoded_x_offset),
        .y_offset(decoded_y_offset),
        .scale_numerator(decoded_scale_numerator),
        .scale_denominator(decoded_scale_denominator),
        .source_row_bytes(decoded_source_row_bytes),
        .source_row_stride(decoded_source_row_stride),
        .source_data_bytes(decoded_source_data_bytes)
    );

    // Parallel half-word comparisons avoid a 32-bit serial carry chain.
    // Strict unsigned ordering is unchanged, including equal high halves.
    function less_u32;
        input [31:0] left_value,right_value;
        begin
            less_u32=(left_value[31:16] < right_value[31:16]) ||
                ((left_value[31:16] == right_value[31:16]) &&
                 (left_value[15:0] < right_value[15:0]));
        end
    endfunction

    task enter_error;
        input [7:0] code;
        begin
            error_code <= code;
            bmp_error <= 1'b1;
            pix_valid <= 1'b0;
            row_pixel_valid <= 1'b0;
            payload_incomplete_q <= 1'b0;
            state <= ST_ERROR;
        end
    endtask

    task begin_row_emit;
        begin
            output_x <= 11'd0;
            source_emit_x <= 11'd0;
            horizontal_phase <= 4'd0;
            pix_valid <= 1'b0;
            row_pixel_valid <= 1'b0;
            state <= ST_EMIT_ROW;
        end
    endtask

    task complete_output_pixel;
        begin
            if (output_x == OUTPUT_WIDTH - 1) begin
                output_x <= 11'd0;
                source_emit_x <= 11'd0;
                horizontal_phase <= 4'd0;
                row_pixel_valid <= 1'b0;
                if (output_y == OUTPUT_HEIGHT - 1) begin
                    state <= ST_WAIT_END;
                end else begin
                    output_y <= output_y + 1'b1;
                    if (vertical_phase_sum >= active_scale_numerator) begin
                        vertical_phase <= vertical_phase_sum -
                                          active_scale_numerator;
                        if (physical_row < active_source_height - 1'b1) begin
                            physical_row <= physical_row + 1'b1;
                            source_x <= 11'd0;
                            row_byte_pos <= 13'd0;
                            channel_phase <= 2'd0;
                            state <= ST_LOAD_ROW;
                        end else begin
                            enter_error(ERR_UNSUPPORTED_PROFILE);
                        end
                    end else begin
                        vertical_phase <= vertical_phase_sum[3:0];
                    end
                end
            end else begin
                output_x <= output_x + 1'b1;
            end
        end
    endtask

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ST_IDLE;
            header_file_size_q <= 32'd0;
            header_pixel_offset_q <= 32'd0;
            dib_size_q <= 32'd0;
            image_width_q <= 32'd0;
            image_height_q <= 32'd0;
            image_data_size_q <= 32'd0;
            signature_matches <= 1'b1;
            planes_match <= 1'b1;
            bpp_matches <= 1'b1;
            compression_matches <= 1'b1;
            expected_offset <= 32'd0;
            pixel_offset <= 32'd0;
            required_end <= 32'd0;
            required_end_overflow <= 1'b0;
            allowed_end <= 32'd0;
            allowed_end_overflow <= 1'b0;
            file_size_q <= 32'd0;
            source_data_bytes_q <= 32'd0;
            size_result_q <= SIZE_RESULT_OK;
            active_profile_id <= 2'd0;
            active_source_width <= 11'd0;
            active_source_height <= 10'd0;
            active_scaled_width <= 11'd0;
            active_scaled_height <= 10'd0;
            active_x_offset <= 11'd0;
            active_y_offset <= 10'd0;
            active_scale_numerator <= 3'd0;
            active_scale_denominator <= 3'd0;
            active_source_row_bytes <= 13'd0;
            active_source_row_stride <= 13'd0;
            physical_row <= 10'd0;
            source_x <= 11'd0;
            row_byte_pos <= 13'd0;
            channel_phase <= 2'd0;
            blue_hold <= 8'd0;
            green_hold <= 8'd0;
            output_x <= 11'd0;
            output_y <= 10'd0;
            source_emit_x <= 11'd0;
            horizontal_phase <= 4'd0;
            vertical_phase <= 4'd0;
            row_pixel_valid <= 1'b0;
            file_done_seen <= 1'b0;
            payload_incomplete_q <= 1'b0;
            pix_valid <= 1'b0;
            pix_rgb888 <= 24'd0;
            bmp_done <= 1'b0;
            bmp_error <= 1'b0;
            error_code <= 8'd0;
            header_accepted <= 1'b0;
        end else begin
            bmp_done <= 1'b0;

            if (start) begin
                state <= ST_HEADER;
                header_file_size_q <= 32'd0;
                header_pixel_offset_q <= 32'd0;
                dib_size_q <= 32'd0;
                image_width_q <= 32'd0;
                image_height_q <= 32'd0;
                image_data_size_q <= 32'd0;
                signature_matches <= 1'b1;
                planes_match <= 1'b1;
                bpp_matches <= 1'b1;
                compression_matches <= 1'b1;
                expected_offset <= 32'd0;
                pixel_offset <= 32'd0;
                required_end <= 32'd0;
                required_end_overflow <= 1'b0;
                allowed_end <= 32'd0;
                allowed_end_overflow <= 1'b0;
                file_size_q <= file_size;
                source_data_bytes_q <= 32'd0;
                size_result_q <= SIZE_RESULT_OK;
                physical_row <= 10'd0;
                source_x <= 11'd0;
                row_byte_pos <= 13'd0;
                channel_phase <= 2'd0;
                output_x <= 11'd0;
                output_y <= 10'd0;
                source_emit_x <= 11'd0;
                horizontal_phase <= 4'd0;
                vertical_phase <= 4'd0;
                row_pixel_valid <= 1'b0;
                file_done_seen <= 1'b0;
                payload_incomplete_q <= 1'b0;
                pix_valid <= 1'b0;
                bmp_error <= 1'b0;
                error_code <= 8'd0;
                header_accepted <= 1'b0;
            end else if (abort && state != ST_IDLE && state != ST_ERROR) begin
                enter_error(ERR_ABORT);
            end else begin
                if (file_done)
                    file_done_seen <= 1'b1;

                if (file_done && upstream_error != 0) begin
                    enter_error(ERR_UPSTREAM);
                end else if (file_done && state == ST_HEADER) begin
                    enter_error(ERR_TRUNCATED);
                end else if (file_done && payload_incomplete_q) begin
                    enter_error(ERR_TRUNCATED);
                end else begin
                    case (state)
                        ST_IDLE: begin end

                        ST_HEADER: begin
                            if (accept_file_byte) begin
                                if (file_byte_offset != expected_offset) begin
                                    enter_error(ERR_ORDER);
                                end else begin
                                    expected_offset <= expected_offset + 1'b1;
                                    case(file_byte_offset[5:0])
                                        6'd0:signature_matches<=file_byte=="B";
                                        6'd1:signature_matches<=signature_matches && file_byte=="M";
                                        6'd2:header_file_size_q[7:0]<=file_byte;
                                        6'd3:header_file_size_q[15:8]<=file_byte;
                                        6'd4:header_file_size_q[23:16]<=file_byte;
                                        6'd5:header_file_size_q[31:24]<=file_byte;
                                        6'd10:header_pixel_offset_q[7:0]<=file_byte;
                                        6'd11:header_pixel_offset_q[15:8]<=file_byte;
                                        6'd12:header_pixel_offset_q[23:16]<=file_byte;
                                        6'd13:header_pixel_offset_q[31:24]<=file_byte;
                                        6'd14:dib_size_q[7:0]<=file_byte;
                                        6'd15:dib_size_q[15:8]<=file_byte;
                                        6'd16:dib_size_q[23:16]<=file_byte;
                                        6'd17:dib_size_q[31:24]<=file_byte;
                                        6'd18:image_width_q[7:0]<=file_byte;
                                        6'd19:image_width_q[15:8]<=file_byte;
                                        6'd20:image_width_q[23:16]<=file_byte;
                                        6'd21:image_width_q[31:24]<=file_byte;
                                        6'd22:image_height_q[7:0]<=file_byte;
                                        6'd23:image_height_q[15:8]<=file_byte;
                                        6'd24:image_height_q[23:16]<=file_byte;
                                        6'd25:image_height_q[31:24]<=file_byte;
                                        6'd26:planes_match<=file_byte==8'd1;
                                        6'd27:planes_match<=planes_match && file_byte==8'd0;
                                        6'd28:bpp_matches<=file_byte==8'd24;
                                        6'd29:bpp_matches<=bpp_matches && file_byte==8'd0;
                                        6'd30:compression_matches<=file_byte==8'd0;
                                        6'd31,6'd32,6'd33:
                                            compression_matches<=compression_matches && file_byte==8'd0;
                                        6'd34:image_data_size_q[7:0]<=file_byte;
                                        6'd35:image_data_size_q[15:8]<=file_byte;
                                        6'd36:image_data_size_q[23:16]<=file_byte;
                                        6'd37:image_data_size_q[31:24]<=file_byte;
                                        default:begin end
                                    endcase
                                    if (file_byte_offset == 32'd53) begin
                                        pixel_offset <= header_pixel_offset_q;
                                        file_size_q <= file_size;
                                        state <= ST_VALIDATE;
                                    end
                                end
                            end
                        end

                        ST_VALIDATE: begin
                            if (!signature_matches) begin
                                enter_error(ERR_SIGNATURE);
                            end else if (dib_size_q != 40 ||
                                         image_width_q == 0 || image_width_q[31] ||
                                         image_height_q == 0 || image_height_q[31]) begin
                                enter_error(ERR_DIMENSIONS);
                            end else if (!planes_match) begin
                                enter_error(ERR_PLANES);
                            end else if (!bpp_matches) begin
                                enter_error(ERR_BPP);
                            end else if (!compression_matches) begin
                                enter_error(ERR_COMPRESSION);
                            end else begin
                                source_data_bytes_q <= decoded_source_data_bytes;
                                state <= ST_BOUNDS;
                            end
                        end

                        ST_BOUNDS: begin
                            if (pixel_offset < 54 ||
                                less_u32(MAX_BMP_PIXEL_OFFSET_VALUE,pixel_offset) ||
                                !less_u32(pixel_offset,file_size_q) ||
                                header_file_size_q != file_size_q) begin
                                enter_error(ERR_OFFSET);
                            end else if (!decoded_profile_valid ||
                                         !decoded_geometry_valid) begin
                                enter_error(ERR_UNSUPPORTED_PROFILE);
                            end else if (image_data_size_q != 0 &&
                                         image_data_size_q !=
                                         source_data_bytes_q) begin
                                enter_error(ERR_OFFSET);
                            end else begin
                                active_profile_id <= decoded_profile_id;
                                active_source_width <= decoded_source_width;
                                active_source_height <= decoded_source_height;
                                active_scaled_width <= decoded_scaled_width;
                                active_scaled_height <= decoded_scaled_height;
                                active_x_offset <= decoded_x_offset;
                                active_y_offset <= decoded_y_offset;
                                active_scale_numerator <= decoded_scale_numerator;
                                active_scale_denominator <= decoded_scale_denominator;
                                active_source_row_bytes <= decoded_source_row_bytes;
                                active_source_row_stride <= decoded_source_row_stride;
                                {required_end_overflow,required_end} <=
                                    {1'b0,pixel_offset} +
                                    {1'b0,source_data_bytes_q};
                                {allowed_end_overflow,allowed_end} <=
                                    {1'b0,pixel_offset} +
                                    {1'b0,source_data_bytes_q} +
                                    MAX_BMP_TRAILING_BYTES_VALUE;
                                state <= ST_SIZE;
                            end
                        end

                        ST_SIZE: begin
                            if (required_end_overflow ||
                                less_u32(file_size_q,required_end) ||
                                (!allowed_end_overflow &&
                                 less_u32(allowed_end,file_size_q))) begin
                                size_result_q <= SIZE_RESULT_OFFSET;
                            end else if ((file_done_seen || file_done) &&
                                         expected_offset < required_end) begin
                                size_result_q <= SIZE_RESULT_TRUNCATED;
                            end else begin
                                size_result_q <= SIZE_RESULT_OK;
                            end
                            state <= ST_SIZE_COMMIT;
                        end

                        ST_SIZE_COMMIT: begin
                            if (size_result_q == SIZE_RESULT_OFFSET) begin
                                enter_error(ERR_OFFSET);
                            end else if (size_result_q ==
                                         SIZE_RESULT_TRUNCATED) begin
                                enter_error(ERR_TRUNCATED);
                            end else if (file_done_seen || file_done) begin
                                enter_error(ERR_TRUNCATED);
                            end else begin
                                header_accepted <= 1'b1;
                                payload_incomplete_q <= 1'b1;
                                if (pixel_offset == 54) begin
                                    state <= ST_LOAD_ROW;
                                end else begin
                                    pixel_offset <= pixel_offset - 1'b1;
                                    state <= ST_SKIP;
                                end
                            end
                        end

                        ST_SKIP: begin
                            if (accept_file_byte) begin
                                if (file_byte_offset != expected_offset) begin
                                    enter_error(ERR_ORDER);
                                end else begin
                                    expected_offset <= expected_offset + 1'b1;
                                    if (file_byte_offset == pixel_offset)
                                        state <= ST_LOAD_ROW;
                                end
                            end
                        end

                        ST_LOAD_ROW: begin
                            if (accept_file_byte) begin
                                if (file_byte_offset != expected_offset) begin
                                    enter_error(ERR_ORDER);
                                end else begin
                                    expected_offset <= expected_offset + 1'b1;
                                    row_byte_pos <= row_byte_pos + 1'b1;
                                    case (channel_phase)
                                        2'd0: begin
                                            blue_hold <= file_byte;
                                            channel_phase <= 2'd1;
                                        end
                                        2'd1: begin
                                            green_hold <= file_byte;
                                            channel_phase <= 2'd2;
                                        end
                                        default: begin
                                            channel_phase <= 2'd0;
                                            if (source_x == active_source_width - 1'b1) begin
                                                if (active_source_row_stride >
                                                    active_source_row_bytes) begin
                                                    row_byte_pos <= active_source_row_bytes;
                                                    state <= ST_PADDING;
                                                end else begin
                                                    if (physical_row ==
                                                        active_source_height - 1'b1)
                                                        payload_incomplete_q <= 1'b0;
                                                    begin_row_emit();
                                                end
                                            end else begin
                                                source_x <= source_x + 1'b1;
                                            end
                                        end
                                    endcase
                                end
                            end
                        end

                        ST_PADDING: begin
                            if (accept_file_byte) begin
                                if (file_byte_offset != expected_offset) begin
                                    enter_error(ERR_ORDER);
                                end else begin
                                    expected_offset <= expected_offset + 1'b1;
                                    if (row_byte_pos ==
                                        active_source_row_stride - 1'b1) begin
                                        if (physical_row ==
                                            active_source_height - 1'b1)
                                            payload_incomplete_q <= 1'b0;
                                        begin_row_emit();
                                    end else begin
                                        row_byte_pos <= row_byte_pos + 1'b1;
                                    end
                                end
                            end
                        end

                        ST_EMIT_ROW: begin
                            if (pix_valid) begin
                                if (pix_req) begin
                                    pix_valid <= 1'b0;
                                    if (output_x >= active_x_offset &&
                                        output_x < active_x_offset +
                                                   active_scaled_width) begin
                                        if (horizontal_phase_sum >=
                                            active_scale_numerator) begin
                                            horizontal_phase <= horizontal_phase_sum -
                                                                active_scale_numerator;
                                            if (source_emit_x <
                                                active_source_width - 1'b1)
                                                source_emit_x <= source_emit_x + 1'b1;
                                        end else begin
                                            horizontal_phase <=
                                                horizontal_phase_sum[3:0];
                                        end
                                    end
                                    complete_output_pixel();
                                end
                            end else if (output_x < active_x_offset ||
                                         output_x >= active_x_offset +
                                                     active_scaled_width) begin
                                pix_valid <= 1'b1;
                                pix_rgb888 <= 24'h000000;
                            end else if (!row_pixel_valid) begin
                                row_pixel_valid <= 1'b1;
                            end else begin
                                pix_valid <= 1'b1;
                                pix_rgb888 <= row_pixel_hold;
                                row_pixel_valid <= 1'b0;
                            end
                        end

                        ST_WAIT_END: begin
                            if (accept_file_byte &&
                                file_byte_offset != expected_offset) begin
                                enter_error(ERR_ORDER);
                            end else begin
                                if (accept_file_byte)
                                    expected_offset <= expected_offset + 1'b1;
                                if (file_done_seen)
                                    state <= ST_DONE;
                            end
                        end

                        ST_DONE: begin
                            bmp_done <= 1'b1;
                            state <= ST_IDLE;
                        end

                        ST_ERROR: begin
                            bmp_error <= 1'b1;
                        end

                        default: state <= ST_IDLE;
                    endcase
                end
            end
        end
    end
endmodule
