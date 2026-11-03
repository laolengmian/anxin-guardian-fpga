`timescale 1ns/1ps

// Six-digit active-low error page: E<stage>-<code_hi><code_lo><blank>.
module m6c_error_seg7 #(
    parameter integer SCAN_STEP_CYCLES = 8192
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       active,
    input  wire [2:0] error_stage,
    input  wire [7:0] error_code,
    output reg  [7:0] seg_n,
    output reg  [5:0] dig_n
);
    localparam integer COUNT_BITS =
        (SCAN_STEP_CYCLES <= 1) ? 1 : $clog2(SCAN_STEP_CYCLES);
    localparam [4:0] F_BLANK = 5'h10;
    localparam [4:0] F_DASH  = 5'h19;
    localparam [4:0] F_E     = 5'h1a;

    reg [COUNT_BITS-1:0] scan_count;
    reg [2:0] scan_index;
    reg [4:0] symbols [0:5];

    function [6:0] seg_font;
        input [4:0] symbol;
        begin
            case (symbol)
                5'h00: seg_font = 7'h3f;
                5'h01: seg_font = 7'h06;
                5'h02: seg_font = 7'h5b;
                5'h03: seg_font = 7'h4f;
                5'h04: seg_font = 7'h66;
                5'h05: seg_font = 7'h6d;
                5'h06: seg_font = 7'h7d;
                5'h07: seg_font = 7'h07;
                5'h08: seg_font = 7'h7f;
                5'h09: seg_font = 7'h6f;
                5'h0a: seg_font = 7'h77;
                5'h0b: seg_font = 7'h7c;
                5'h0c: seg_font = 7'h39;
                5'h0d: seg_font = 7'h5e;
                5'h0e, F_E: seg_font = 7'h79;
                5'h0f: seg_font = 7'h71;
                F_DASH: seg_font = 7'h40;
                default: seg_font = 7'h00;
            endcase
        end
    endfunction

    always @* begin
        symbols[0] = F_E;
        symbols[1] = {2'd0, error_stage};
        symbols[2] = F_DASH;
        symbols[3] = {1'b0, error_code[7:4]};
        symbols[4] = {1'b0, error_code[3:0]};
        symbols[5] = F_BLANK;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            scan_count <= 0;
            scan_index <= 3'd0;
            seg_n <= 8'hff;
            dig_n <= 6'h3f;
        end else if (!active) begin
            scan_count <= 0;
            scan_index <= 3'd0;
            seg_n <= 8'hff;
            dig_n <= 6'h3f;
        end else begin
            if (scan_count == SCAN_STEP_CYCLES - 1) begin
                scan_count <= 0;
                scan_index <= scan_index == 3'd5 ? 3'd0 : scan_index + 1'b1;
            end else
                scan_count <= scan_count + 1'b1;
            dig_n <= ~(6'b000001 << scan_index);
            seg_n <= {1'b1, ~seg_font(symbols[scan_index])};
        end
    end
endmodule
