`timescale 1ns/1ps
// Frame-coherent vital-value overlay with independent input validity.
module m9_vital_monitor_overlay (
    input wire clk,
    input wire rst,
    input wire in_valid,
    input wire in_user,
    input wire in_last,
    input wire [14:0] in_x,
    input wire [14:0] in_y,
    input wire [23:0] in_rgb,
    input wire diagnostic_pending,
    input wire alert_active_pending,
    input wire monitor_update,
    input wire [7:0] hr_bpm,
    input wire [7:0] spo2_percent,
    input wire [7:0] rr_bpm,
    input wire hr_valid,
    input wire spo2_valid,
    input wire rr_valid,
    input wire [1:0] data_source,
    input wire [11:0] hr_bcd,
    input wire [11:0] spo2_bcd,
    input wire [11:0] rr_bcd,
    input wire [3:0] brightness_level_pending,
    input wire brightness_update,
    output reg out_valid,
    output reg out_user,
    output reg out_last,
    output reg [14:0] out_x,
    output reg [14:0] out_y,
    output reg [23:0] out_rgb
);
    localparam [23:0] PANEL_BG = 24'hf7fafe;
    localparam [23:0] TITLE = 24'h145da0;
    localparam [23:0] TEXT = 24'h16436a;
    localparam [23:0] GOOD = 24'h137a55;
    localparam [23:0] MUTED = 24'h657d91;
    localparam [23:0] BORDER = 24'hd7e4ee;

    wire first = in_valid && in_user;
    wire in_canvas = (in_x[14:11] == 4'd0) && (in_y[14:10] == 5'd0);
    wire [10:0] pixel_x = in_x[10:0];
    wire [9:0] pixel_y = in_y[9:0];
    wire in_card = in_canvas &&
                   pixel_x >= 11'd1032 && pixel_x < 11'd1256 &&
                   pixel_y >= 10'd184 && pixel_y < 10'd424;

    reg [104:0] pending_hr_rows, pending_spo2_rows, pending_rr_rows;
    reg pending_hr_valid, pending_spo2_valid, pending_rr_valid;
    reg [1:0] pending_source;
    reg [104:0] frame_hr_rows, frame_spo2_rows, frame_rr_rows;
    reg frame_hr_valid, frame_spo2_valid, frame_rr_valid;
    reg [1:0] frame_source;
    reg diagnostic_q, alert_q;
    reg [3:0] pending_brightness,frame_brightness;

    function [4:0] glyph_row;
        input [7:0] character;
        input [2:0] row_index;
        begin
            glyph_row = 5'b00000;
            case (character)
                8'h30: case(row_index) 0:glyph_row=5'b01110;1:glyph_row=5'b10001;
                    2:glyph_row=5'b10011;3:glyph_row=5'b10101;4:glyph_row=5'b11001;
                    5:glyph_row=5'b10001;6:glyph_row=5'b01110;default:glyph_row=0;endcase
                8'h31: case(row_index) 0:glyph_row=5'b00100;1:glyph_row=5'b01100;
                    2:glyph_row=5'b00100;3:glyph_row=5'b00100;4:glyph_row=5'b00100;
                    5:glyph_row=5'b00100;6:glyph_row=5'b01110;default:glyph_row=0;endcase
                8'h32: case(row_index) 0:glyph_row=5'b01110;1:glyph_row=5'b10001;
                    2:glyph_row=5'b00001;3:glyph_row=5'b00010;4:glyph_row=5'b00100;
                    5:glyph_row=5'b01000;6:glyph_row=5'b11111;default:glyph_row=0;endcase
                8'h33: case(row_index) 0:glyph_row=5'b11110;1:glyph_row=5'b00001;
                    2:glyph_row=5'b00001;3:glyph_row=5'b01110;4:glyph_row=5'b00001;
                    5:glyph_row=5'b00001;6:glyph_row=5'b11110;default:glyph_row=0;endcase
                8'h34: case(row_index) 0:glyph_row=5'b00010;1:glyph_row=5'b00110;
                    2:glyph_row=5'b01010;3:glyph_row=5'b10010;4:glyph_row=5'b11111;
                    5:glyph_row=5'b00010;6:glyph_row=5'b00010;default:glyph_row=0;endcase
                8'h35: case(row_index) 0:glyph_row=5'b11111;1:glyph_row=5'b10000;
                    2:glyph_row=5'b10000;3:glyph_row=5'b11110;4:glyph_row=5'b00001;
                    5:glyph_row=5'b00001;6:glyph_row=5'b11110;default:glyph_row=0;endcase
                8'h36: case(row_index) 0:glyph_row=5'b01110;1:glyph_row=5'b10000;
                    2:glyph_row=5'b10000;3:glyph_row=5'b11110;4:glyph_row=5'b10001;
                    5:glyph_row=5'b10001;6:glyph_row=5'b01110;default:glyph_row=0;endcase
                8'h37: case(row_index) 0:glyph_row=5'b11111;1:glyph_row=5'b00001;
                    2:glyph_row=5'b00010;3:glyph_row=5'b00100;4:glyph_row=5'b01000;
                    5:glyph_row=5'b01000;6:glyph_row=5'b01000;default:glyph_row=0;endcase
                8'h38: case(row_index) 0:glyph_row=5'b01110;1:glyph_row=5'b10001;
                    2:glyph_row=5'b10001;3:glyph_row=5'b01110;4:glyph_row=5'b10001;
                    5:glyph_row=5'b10001;6:glyph_row=5'b01110;default:glyph_row=0;endcase
                8'h39: case(row_index) 0:glyph_row=5'b01110;1:glyph_row=5'b10001;
                    2:glyph_row=5'b10001;3:glyph_row=5'b01111;4:glyph_row=5'b00001;
                    5:glyph_row=5'b00001;6:glyph_row=5'b01110;default:glyph_row=0;endcase
                8'h42: case(row_index) 0:glyph_row=5'b11110;1:glyph_row=5'b10001;
                    2:glyph_row=5'b10001;3:glyph_row=5'b11110;4:glyph_row=5'b10001;
                    5:glyph_row=5'b10001;6:glyph_row=5'b11110;default:glyph_row=0;endcase
                8'h44: case(row_index) 0:glyph_row=5'b11110;1:glyph_row=5'b10001;
                    2:glyph_row=5'b10001;3:glyph_row=5'b10001;4:glyph_row=5'b10001;
                    5:glyph_row=5'b10001;6:glyph_row=5'b11110;default:glyph_row=0;endcase
                8'h45: case(row_index) 0:glyph_row=5'b11111;1:glyph_row=5'b10000;
                    2:glyph_row=5'b10000;3:glyph_row=5'b11110;4:glyph_row=5'b10000;
                    5:glyph_row=5'b10000;6:glyph_row=5'b11111;default:glyph_row=0;endcase
                8'h48: case(row_index) 0:glyph_row=5'b10001;1:glyph_row=5'b10001;
                    2:glyph_row=5'b10001;3:glyph_row=5'b11111;4:glyph_row=5'b10001;
                    5:glyph_row=5'b10001;6:glyph_row=5'b10001;default:glyph_row=0;endcase
                8'h4d: case(row_index) 0:glyph_row=5'b10001;1:glyph_row=5'b11011;
                    2:glyph_row=5'b10101;3:glyph_row=5'b10101;4:glyph_row=5'b10001;
                    5:glyph_row=5'b10001;6:glyph_row=5'b10001;default:glyph_row=0;endcase
                8'h4f: case(row_index) 0:glyph_row=5'b01110;1:glyph_row=5'b10001;
                    2:glyph_row=5'b10001;3:glyph_row=5'b10001;4:glyph_row=5'b10001;
                    5:glyph_row=5'b10001;6:glyph_row=5'b01110;default:glyph_row=0;endcase
                8'h50: case(row_index) 0:glyph_row=5'b11110;1:glyph_row=5'b10001;
                    2:glyph_row=5'b10001;3:glyph_row=5'b11110;4:glyph_row=5'b10000;
                    5:glyph_row=5'b10000;6:glyph_row=5'b10000;default:glyph_row=0;endcase
                8'h52: case(row_index) 0:glyph_row=5'b11110;1:glyph_row=5'b10001;
                    2:glyph_row=5'b10001;3:glyph_row=5'b11110;4:glyph_row=5'b10100;
                    5:glyph_row=5'b10010;6:glyph_row=5'b10001;default:glyph_row=0;endcase
                8'h53: case(row_index) 0:glyph_row=5'b11110;1:glyph_row=5'b10000;
                    2:glyph_row=5'b10000;3:glyph_row=5'b01110;4:glyph_row=5'b00001;
                    5:glyph_row=5'b00001;6:glyph_row=5'b11110;default:glyph_row=0;endcase
                8'h25: case(row_index) 0:glyph_row=5'b11001;1:glyph_row=5'b11010;
                    2:glyph_row=5'b00100;3:glyph_row=5'b01000;4:glyph_row=5'b10110;
                    5:glyph_row=5'b00110;default:glyph_row=0;endcase
                8'h2d: case(row_index) 3:glyph_row=5'b11111;default:glyph_row=0;endcase
                default: glyph_row=5'b00000;
            endcase
        end
    endfunction

    // A narrow BCD decoder removes the 8-bit character adder from every
    // monitored value path. Out-of-range and unknown digits remain blank.
    function [4:0] digit_row;
        input [3:0] digit;
        input [2:0] row_index;
        begin
            digit_row = 5'b00000;
            case (digit)
                4'd0: case(row_index) 0:digit_row=5'b01110;1:digit_row=5'b10001;
                    2:digit_row=5'b10011;3:digit_row=5'b10101;4:digit_row=5'b11001;
                    5:digit_row=5'b10001;6:digit_row=5'b01110;default:digit_row=0;endcase
                4'd1: case(row_index) 0:digit_row=5'b00100;1:digit_row=5'b01100;
                    2:digit_row=5'b00100;3:digit_row=5'b00100;4:digit_row=5'b00100;
                    5:digit_row=5'b00100;6:digit_row=5'b01110;default:digit_row=0;endcase
                4'd2: case(row_index) 0:digit_row=5'b01110;1:digit_row=5'b10001;
                    2:digit_row=5'b00001;3:digit_row=5'b00010;4:digit_row=5'b00100;
                    5:digit_row=5'b01000;6:digit_row=5'b11111;default:digit_row=0;endcase
                4'd3: case(row_index) 0:digit_row=5'b11110;1:digit_row=5'b00001;
                    2:digit_row=5'b00001;3:digit_row=5'b01110;4:digit_row=5'b00001;
                    5:digit_row=5'b00001;6:digit_row=5'b11110;default:digit_row=0;endcase
                4'd4: case(row_index) 0:digit_row=5'b00010;1:digit_row=5'b00110;
                    2:digit_row=5'b01010;3:digit_row=5'b10010;4:digit_row=5'b11111;
                    5:digit_row=5'b00010;6:digit_row=5'b00010;default:digit_row=0;endcase
                4'd5: case(row_index) 0:digit_row=5'b11111;1:digit_row=5'b10000;
                    2:digit_row=5'b10000;3:digit_row=5'b11110;4:digit_row=5'b00001;
                    5:digit_row=5'b00001;6:digit_row=5'b11110;default:digit_row=0;endcase
                4'd6: case(row_index) 0:digit_row=5'b01110;1:digit_row=5'b10000;
                    2:digit_row=5'b10000;3:digit_row=5'b11110;4:digit_row=5'b10001;
                    5:digit_row=5'b10001;6:digit_row=5'b01110;default:digit_row=0;endcase
                4'd7: case(row_index) 0:digit_row=5'b11111;1:digit_row=5'b00001;
                    2:digit_row=5'b00010;3:digit_row=5'b00100;4:digit_row=5'b01000;
                    5:digit_row=5'b01000;6:digit_row=5'b01000;default:digit_row=0;endcase
                4'd8: case(row_index) 0:digit_row=5'b01110;1:digit_row=5'b10001;
                    2:digit_row=5'b10001;3:digit_row=5'b01110;4:digit_row=5'b10001;
                    5:digit_row=5'b10001;6:digit_row=5'b01110;default:digit_row=0;endcase
                4'd9: case(row_index) 0:digit_row=5'b01110;1:digit_row=5'b10001;
                    2:digit_row=5'b10001;3:digit_row=5'b01111;4:digit_row=5'b00001;
                    5:digit_row=5'b00001;6:digit_row=5'b01110;default:digit_row=0;endcase
                default: digit_row = 5'b00000;
            endcase
        end
    endfunction

    function row_pixel;
        input [4:0] row_bits;
        input [2:0] column_index;
        begin
            case (column_index)
                0: row_pixel = row_bits[4];
                1: row_pixel = row_bits[3];
                2: row_pixel = row_bits[2];
                3: row_pixel = row_bits[1];
                4: row_pixel = row_bits[0];
                default: row_pixel = 1'b0;
            endcase
        end
    endfunction

    function [4:0] value_row;
        input [11:0] bcd;
        input valid_value;
        input [1:0] value_cell;
        input [2:0] row_index;
        reg [3:0] digit;
        reg blank;
        begin
            digit = 4'd0;
            blank = 1'b0;
            if (!valid_value) begin
                if (value_cell == 2'd1 || value_cell == 2'd2)
                    value_row = glyph_row(8'h2d, row_index);
                else
                    value_row = 5'b00000;
            end else begin
                case (value_cell)
                    2'd0: begin
                        digit = bcd[11:8];
                        blank = bcd[11:8] == 0;
                    end
                    2'd1: begin
                        digit = bcd[7:4];
                        blank = bcd[11:8] == 0 && bcd[7:4] == 0;
                    end
                    default: digit = bcd[3:0];
                endcase
                value_row = blank ? 5'b00000 :
                            digit_row(digit, row_index);
            end
        end
    endfunction

    // Seven rows x three cells x five bits. Live values preserve the original
    // same-edge SOF/update contract; pending/frame state removes the BCD/glyph
    // decoder from every held-value pixel path.
    function [104:0] value_row_set;
        input [11:0] bcd;
        input valid_value;
        begin
            value_row_set = {
                value_row(bcd,valid_value,2'd2,3'd6),value_row(bcd,valid_value,2'd1,3'd6),value_row(bcd,valid_value,2'd0,3'd6),
                value_row(bcd,valid_value,2'd2,3'd5),value_row(bcd,valid_value,2'd1,3'd5),value_row(bcd,valid_value,2'd0,3'd5),
                value_row(bcd,valid_value,2'd2,3'd4),value_row(bcd,valid_value,2'd1,3'd4),value_row(bcd,valid_value,2'd0,3'd4),
                value_row(bcd,valid_value,2'd2,3'd3),value_row(bcd,valid_value,2'd1,3'd3),value_row(bcd,valid_value,2'd0,3'd3),
                value_row(bcd,valid_value,2'd2,3'd2),value_row(bcd,valid_value,2'd1,3'd2),value_row(bcd,valid_value,2'd0,3'd2),
                value_row(bcd,valid_value,2'd2,3'd1),value_row(bcd,valid_value,2'd1,3'd1),value_row(bcd,valid_value,2'd0,3'd1),
                value_row(bcd,valid_value,2'd2,3'd0),value_row(bcd,valid_value,2'd1,3'd0),value_row(bcd,valid_value,2'd0,3'd0)
            };
        end
    endfunction
    function [14:0] select_value_row_set;
        input [104:0] rows;
        input [2:0] row_index;
        begin
            case(row_index)
                0:select_value_row_set=rows[14:0];
                1:select_value_row_set=rows[29:15];
                2:select_value_row_set=rows[44:30];
                3:select_value_row_set=rows[59:45];
                4:select_value_row_set=rows[74:60];
                5:select_value_row_set=rows[89:75];
                6:select_value_row_set=rows[104:90];
                default:select_value_row_set=15'd0;
            endcase
        end
    endfunction
    function [4:0] select_value_cell;
        input [14:0] rows;
        input [1:0] value_cell;
        begin
            case(value_cell)
                2'd0:select_value_cell=rows[4:0];
                2'd1:select_value_cell=rows[9:5];
                default:select_value_cell=rows[14:10];
            endcase
        end
    endfunction

    wire [104:0] live_hr_rows = value_row_set(hr_bcd,hr_valid);
    wire [104:0] live_spo2_rows = value_row_set(spo2_bcd,spo2_valid);
    wire [104:0] live_rr_rows = value_row_set(rr_bcd,rr_valid);
    wire [104:0] visible_hr_rows = first ?
        (monitor_update ? live_hr_rows : pending_hr_rows) : frame_hr_rows;
    wire [104:0] visible_spo2_rows = first ?
        (monitor_update ? live_spo2_rows : pending_spo2_rows) : frame_spo2_rows;
    wire [104:0] visible_rr_rows = first ?
        (monitor_update ? live_rr_rows : pending_rr_rows) : frame_rr_rows;
    wire visible_hr_valid = first ?
        (monitor_update ? hr_valid : pending_hr_valid) : frame_hr_valid;
    wire visible_spo2_valid = first ?
        (monitor_update ? spo2_valid : pending_spo2_valid) : frame_spo2_valid;
    wire visible_rr_valid = first ?
        (monitor_update ? rr_valid : pending_rr_valid) : frame_rr_valid;
    wire [1:0] visible_source = first ?
        (monitor_update ? data_source : pending_source) : frame_source;
    wire visible_diagnostic = first ? diagnostic_pending : diagnostic_q;
    wire visible_alert = first ? alert_active_pending : alert_q;
    wire overlay_active = in_valid && in_card && !visible_diagnostic &&
                          !visible_alert;

    wire title_window=in_canvas && pixel_y>=196 && pixel_y<208 &&
                      pixel_x>=1112 && pixel_x<1160;
    wire source_status_window=1'b0;
    wire hr_label_window=in_canvas && pixel_y>=244 && pixel_y<256 &&
                         pixel_x>=1040 && pixel_x<1064;
    wire spo2_label_window=in_canvas && pixel_y>=300 && pixel_y<312 &&
                           pixel_x>=1040 && pixel_x<1064;
    wire rr_label_window=in_canvas && pixel_y>=356 && pixel_y<368 &&
                         pixel_x>=1040 && pixel_x<1064;
    wire hr_unit_window=in_canvas && pixel_y>=244 && pixel_y<256 &&
                        pixel_x>=1200 && pixel_x<1236;
    wire rr_unit_window=in_canvas && pixel_y>=356 && pixel_y<368 &&
                        pixel_x>=1200 && pixel_x<1236;
    reg [3:0] chinese_column;
    reg chinese_window;
    reg [11:0] chinese_bits;
    wire [3:0] title_row=pixel_y-10'd196;
    wire [3:0] source_status_row=pixel_y-10'd212;
    wire [3:0] hr_label_row=pixel_y-10'd244;
    wire [3:0] spo2_label_row=pixel_y-10'd300;
    wire [3:0] rr_label_row=pixel_y-10'd356;
    wire [3:0] unit_row=hr_unit_window ? pixel_y-10'd244 : pixel_y-10'd356;
    wire [11:0] title_bits_1,title_bits_2,title_bits_3,title_bits_4;
    wire [11:0] source_status_bits_14,source_status_bits_15;
    wire [11:0] hr_label_bits_5,hr_label_bits_6;
    wire [11:0] spo2_label_bits_7,spo2_label_bits_8;
    wire [11:0] rr_label_bits_9,rr_label_bits_10;
    wire [11:0] unit_bits_11,unit_bits_13,unit_bits_12;

    // Constant glyph IDs collapse ROM selection before the final disjoint
    // window mux. No BRAM or video pipeline stage is introduced.
    m9_monitor_chinese_glyph_rom u_title_1(.glyph_id(4'd1),.row(title_row),.bits(title_bits_1));
    m9_monitor_chinese_glyph_rom u_title_2(.glyph_id(4'd2),.row(title_row),.bits(title_bits_2));
    m9_monitor_chinese_glyph_rom u_title_3(.glyph_id(4'd3),.row(title_row),.bits(title_bits_3));
    m9_monitor_chinese_glyph_rom u_title_4(.glyph_id(4'd4),.row(title_row),.bits(title_bits_4));
    m9_monitor_chinese_glyph_rom u_source_status_14(.glyph_id(4'd14),.row(source_status_row),.bits(source_status_bits_14));
    m9_monitor_chinese_glyph_rom u_source_status_15(.glyph_id(4'd15),.row(source_status_row),.bits(source_status_bits_15));
    m9_monitor_chinese_glyph_rom u_hr_label_5(.glyph_id(4'd5),.row(hr_label_row),.bits(hr_label_bits_5));
    m9_monitor_chinese_glyph_rom u_hr_label_6(.glyph_id(4'd6),.row(hr_label_row),.bits(hr_label_bits_6));
    m9_monitor_chinese_glyph_rom u_spo2_label_7(.glyph_id(4'd7),.row(spo2_label_row),.bits(spo2_label_bits_7));
    m9_monitor_chinese_glyph_rom u_spo2_label_8(.glyph_id(4'd8),.row(spo2_label_row),.bits(spo2_label_bits_8));
    m9_monitor_chinese_glyph_rom u_rr_label_9(.glyph_id(4'd9),.row(rr_label_row),.bits(rr_label_bits_9));
    m9_monitor_chinese_glyph_rom u_rr_label_10(.glyph_id(4'd10),.row(rr_label_row),.bits(rr_label_bits_10));
    m9_monitor_chinese_glyph_rom u_unit_11(.glyph_id(4'd11),.row(unit_row),.bits(unit_bits_11));
    m9_monitor_chinese_glyph_rom u_unit_13(.glyph_id(4'd13),.row(unit_row),.bits(unit_bits_13));
    m9_monitor_chinese_glyph_rom u_unit_12(.glyph_id(4'd12),.row(unit_row),.bits(unit_bits_12));

    always @(*) begin
        chinese_column=0;chinese_window=0;chinese_bits=0;
        if(title_window) begin
            chinese_window=1;
            if(pixel_x<1124) begin chinese_bits=title_bits_1;chinese_column=pixel_x-1112;end
            else if(pixel_x<1136) begin chinese_bits=title_bits_2;chinese_column=pixel_x-1124;end
            else if(pixel_x<1148) begin chinese_bits=title_bits_3;chinese_column=pixel_x-1136;end
            else begin chinese_bits=title_bits_4;chinese_column=pixel_x-1148;end
        end else if(source_status_window) begin
            chinese_window=1;
            if(pixel_x<1136) begin chinese_bits=source_status_bits_14;chinese_column=pixel_x-1124;end
            else begin chinese_bits=source_status_bits_15;chinese_column=pixel_x-1136;end
        end else if(hr_label_window || spo2_label_window || rr_label_window) begin
            chinese_window=1;chinese_column=pixel_x>=1052 ? pixel_x-1052 : pixel_x-1040;
            if(hr_label_window)
                chinese_bits=pixel_x>=1052 ? hr_label_bits_6 : hr_label_bits_5;
            else if(spo2_label_window)
                chinese_bits=pixel_x>=1052 ? spo2_label_bits_8 : spo2_label_bits_7;
            else
                chinese_bits=pixel_x>=1052 ? rr_label_bits_10 : rr_label_bits_9;
        end else if(hr_unit_window || rr_unit_window) begin
            chinese_window=1;
            if(pixel_x<1212) begin chinese_bits=unit_bits_11;chinese_column=pixel_x-1200;end
            else if(pixel_x<1224) begin chinese_bits=unit_bits_13;chinese_column=pixel_x-1212;end
            else begin chinese_bits=unit_bits_12;chinese_column=pixel_x-1224;end
        end
    end
    wire chinese_pixel_on=chinese_window && chinese_bits[11-chinese_column];

    wire hr_value_window = in_canvas && pixel_y >= 10'd236 && pixel_y < 10'd264 &&
                           pixel_x >= 11'd1088 && pixel_x < 11'd1184;
    wire [10:0] hr_value_dx = pixel_x - 11'd1088;
    wire [9:0] hr_value_dy = pixel_y - 10'd236;
    wire [14:0] hr_rows_at_pixel = select_value_row_set(visible_hr_rows,hr_value_dy[4:2]);
    wire [4:0] hr_value_row = select_value_cell(hr_rows_at_pixel,hr_value_dx[6:5]);
    wire hr_value_pixel_on = hr_value_window && hr_value_dx[4:0] < 20 &&
                             row_pixel(hr_value_row, hr_value_dx[4:2]);

    wire spo2_value_window = in_canvas && pixel_y >= 10'd292 && pixel_y < 10'd320 &&
                             pixel_x >= 11'd1104 && pixel_x < 11'd1200;
    wire [10:0] spo2_value_dx = pixel_x - 11'd1104;
    wire [9:0] spo2_value_dy = pixel_y - 10'd292;
    wire [14:0] spo2_rows_at_pixel = select_value_row_set(visible_spo2_rows,spo2_value_dy[4:2]);
    wire [4:0] spo2_value_row = select_value_cell(spo2_rows_at_pixel,spo2_value_dx[6:5]);
    wire spo2_value_pixel_on = spo2_value_window && spo2_value_dx[4:0] < 20 &&
                               row_pixel(spo2_value_row, spo2_value_dx[4:2]);

    wire percent_window = in_canvas && pixel_y >= 10'd300 && pixel_y < 10'd314 &&
                          pixel_x >= 11'd1216 && pixel_x < 11'd1232;
    wire [10:0] percent_dx = pixel_x - 11'd1216;
    wire [9:0] percent_dy = pixel_y - 10'd300;
    wire [4:0] percent_row = glyph_row(8'h25, percent_dy[3:1]);
    wire percent_pixel_on = percent_window && percent_dx[3:0] < 10 &&
                            row_pixel(percent_row, percent_dx[3:1]);

    wire rr_value_window = in_canvas && pixel_y >= 10'd348 && pixel_y < 10'd376 &&
                           pixel_x >= 11'd1088 && pixel_x < 11'd1184;
    wire [10:0] rr_value_dx = pixel_x - 11'd1088;
    wire [9:0] rr_value_dy = pixel_y - 10'd348;
    wire [14:0] rr_rows_at_pixel = select_value_row_set(visible_rr_rows,rr_value_dy[4:2]);
    wire [4:0] rr_value_row = select_value_cell(rr_rows_at_pixel,rr_value_dx[6:5]);
    wire rr_value_pixel_on = rr_value_window && rr_value_dx[4:0] < 20 &&
                             row_pixel(rr_value_row, rr_value_dx[4:2]);

    wire border_pixel_on = pixel_x < 11'd1034 || pixel_x >= 11'd1254 ||
                           pixel_y < 10'd186 || pixel_y >= 10'd422 ||
                           (pixel_y >= 10'd223 && pixel_y < 10'd225) ||
                           (pixel_y >= 10'd279 && pixel_y < 10'd281) ||
                           (pixel_y >= 10'd335 && pixel_y < 10'd337);
    wire [23:0] hr_value_color = visible_hr_valid ? GOOD : MUTED;
    wire [23:0] spo2_value_color = visible_spo2_valid ? GOOD : MUTED;
    wire [23:0] rr_value_color = visible_rr_valid ? GOOD : MUTED;

    wire [3:0] visible_brightness=first ?
        (brightness_update ? brightness_level_pending : pending_brightness) : frame_brightness;
    function signed [8:0] level_offset;
        input [3:0] level;
        begin
            case(level)
                0:level_offset=-9'sd128;1:level_offset=-9'sd96;
                2:level_offset=-9'sd64;3:level_offset=-9'sd32;
                5:level_offset=9'sd16;6:level_offset=9'sd32;
                7:level_offset=9'sd48;8:level_offset=9'sd64;
                default:level_offset=0;
            endcase
        end
    endfunction
    function [7:0] bright_channel;
        input [7:0] channel;input signed [8:0] offset;
        reg signed [9:0] sum;
        begin
            sum=$signed({1'b0,channel})+offset;
            if(sum<0)bright_channel=0;
            else if(sum>255)bright_channel=8'hff;
            else bright_channel=sum[7:0];
        end
    endfunction
    function [23:0] bright_rgb;
        input [23:0] color;input [3:0] level;
        reg signed [8:0] offset;
        begin
            offset=level_offset(level);
            bright_rgb={bright_channel(color[23:16],offset),
                        bright_channel(color[15:8],offset),
                        bright_channel(color[7:0],offset)};
        end
    endfunction

    // Brightness arithmetic is parallel to coordinate/glyph decoding. The final
    // priority mux selects already-adjusted Product colors, preserving one cycle.
    wire [23:0] bright_in_rgb=bright_rgb(in_rgb,visible_brightness);
    wire [23:0] bright_panel_bg=bright_rgb(PANEL_BG,visible_brightness);
    wire [23:0] bright_title=bright_rgb(TITLE,visible_brightness);
    wire [23:0] bright_text=bright_rgb(TEXT,visible_brightness);
    wire [23:0] bright_good=bright_rgb(GOOD,visible_brightness);
    wire [23:0] bright_muted=bright_rgb(MUTED,visible_brightness);
    wire [23:0] bright_border=bright_rgb(BORDER,visible_brightness);
    wire [23:0] bright_hr_value_color=bright_rgb(hr_value_color,visible_brightness);
    wire [23:0] bright_spo2_value_color=bright_rgb(spo2_value_color,visible_brightness);
    wire [23:0] bright_rr_value_color=bright_rgb(rr_value_color,visible_brightness);
    wire product_brightness_active=in_valid && !visible_diagnostic && !visible_alert;

    reg [23:0] rendered_rgb;
    always @(*) begin
        rendered_rgb=product_brightness_active ? bright_in_rgb : in_rgb;
        if(overlay_active) begin
            rendered_rgb=border_pixel_on ? bright_border : bright_panel_bg;
            if(chinese_pixel_on) begin
                if(title_window)
                    rendered_rgb=bright_title;
                else if(source_status_window)
                    rendered_rgb=bright_muted;
                else if(hr_unit_window || rr_unit_window)
                    rendered_rgb=bright_muted;
                else
                    rendered_rgb=bright_text;
            end else if(hr_value_pixel_on)
                rendered_rgb=bright_hr_value_color;
            else if(spo2_value_pixel_on)
                rendered_rgb=bright_spo2_value_color;
            else if(rr_value_pixel_on)
                rendered_rgb=bright_rr_value_color;
            else if(percent_pixel_on)
                rendered_rgb=bright_muted;
        end
    end

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            pending_hr_rows<=value_row_set(12'd0,1'b0);
            pending_spo2_rows<=value_row_set(12'd0,1'b0);
            pending_rr_rows<=value_row_set(12'd0,1'b0);
            pending_hr_valid<=0;pending_spo2_valid<=0;pending_rr_valid<=0;
            pending_source<=0;
            frame_hr_rows<=value_row_set(12'd0,1'b0);
            frame_spo2_rows<=value_row_set(12'd0,1'b0);
            frame_rr_rows<=value_row_set(12'd0,1'b0);
            frame_hr_valid<=0;frame_spo2_valid<=0;frame_rr_valid<=0;
            frame_source<=0;diagnostic_q<=0;alert_q<=0;
            pending_brightness<=4;frame_brightness<=4;
            out_valid<=0;out_user<=0;out_last<=0;out_x<=0;out_y<=0;out_rgb<=0;
        end else begin
            if(brightness_update) pending_brightness<=brightness_level_pending;
            if (monitor_update) begin
                pending_hr_rows<=live_hr_rows;
                pending_spo2_rows<=live_spo2_rows;
                pending_rr_rows<=live_rr_rows;
                pending_hr_valid<=hr_valid;
                pending_spo2_valid<=spo2_valid;
                pending_rr_valid<=rr_valid;
                pending_source<=data_source;
            end
            if (first) begin
                frame_hr_rows<=monitor_update ? live_hr_rows : pending_hr_rows;
                frame_spo2_rows<=monitor_update ? live_spo2_rows : pending_spo2_rows;
                frame_rr_rows<=monitor_update ? live_rr_rows : pending_rr_rows;
                frame_hr_valid<=monitor_update ? hr_valid : pending_hr_valid;
                frame_spo2_valid<=monitor_update ? spo2_valid : pending_spo2_valid;
                frame_rr_valid<=monitor_update ? rr_valid : pending_rr_valid;
                frame_source<=monitor_update ? data_source : pending_source;
                diagnostic_q<=diagnostic_pending;
                alert_q<=alert_active_pending;
                frame_brightness<=brightness_update ? brightness_level_pending : pending_brightness;
            end
            out_valid<=in_valid;
            out_user<=in_user;
            out_last<=in_last;
            out_x<=in_x;
            out_y<=in_y;
            out_rgb<=rendered_rgb;
        end
    end
endmodule
