`timescale 1ns/1ps

// Six connected digits on HX4S20C: seg7_anode[0..5] drive physical
// SEL2..SEL7 from left to right. Pages rotate once per second; an event holds
// its page for two seconds. Segment and digit outputs are active-low.
//
// Physical display strings:
//   PIC__n  n=1..4
//   VOLddd  volume=000..255
//   P-dd-S  period seconds; d=tens/ones (R/D are illegible on seven segments)
module seg7_panel #(
    parameter integer CLK_HZ = 50000000,
    parameter integer SCAN_STEP_CYCLES = 8192,
    parameter integer PAGE_PERIOD_CYCLES = CLK_HZ,
    parameter integer HOLD_CYCLES = 2 * CLK_HZ
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       enable,
    input  wire [1:0] media_id,
    input  wire [7:0] volume,
    input  wire [5:0] period_sec,
    input  wire       pic_event,
    input  wire       vol_event,
    input  wire       prd_event,
    output reg  [7:0] seg_n,
    output reg  [5:0] dig_n
);
    localparam [2:0] PAGE_PIC = 3'd0;
    localparam [2:0] PAGE_VOL = 3'd1;
    localparam [2:0] PAGE_PRD = 3'd2;

    reg [12:0] scan_cnt;
    reg [31:0] page_timer;
    reg [31:0] hold_timer;
    reg [2:0]  page;
    reg        holding;

    // Page selection: rotate normally, or hold the most recent event page.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            page       <= PAGE_PIC;
            page_timer <= 32'd0;
            hold_timer <= 32'd0;
            holding    <= 1'b0;
        end else begin
            if (vol_event) begin
                page <= PAGE_VOL;
                holding <= 1'b1;
                hold_timer <= 32'd0;
            end else if (prd_event) begin
                page <= PAGE_PRD;
                holding <= 1'b1;
                hold_timer <= 32'd0;
            end else if (pic_event) begin
                page <= PAGE_PIC;
                holding <= 1'b1;
                hold_timer <= 32'd0;
            end else if (holding) begin
                if (hold_timer >= HOLD_CYCLES - 1) begin
                    holding    <= 1'b0;
                    hold_timer <= 32'd0;
                    page_timer <= 32'd0;
                end else begin
                    hold_timer <= hold_timer + 1'b1;
                end
            end else if (page_timer >= PAGE_PERIOD_CYCLES - 1) begin
                page_timer <= 32'd0;
                page <= (page == PAGE_PRD) ? PAGE_PIC : page + 1'b1;
            end else begin
                page_timer <= page_timer + 1'b1;
            end
        end
    end

    // Binary 0..255 to three BCD digits without multipliers or dividers.
    function [11:0] bcd8;
        input [7:0] v;
        integer i;
        reg [7:0] src;
        reg [3:0] n0, n1, n2;
        begin
            src = v;
            n0 = 4'd0;
            n1 = 4'd0;
            n2 = 4'd0;
            for (i = 0; i < 8; i = i + 1) begin
                if (n0 >= 5) n0 = n0 + 3;
                if (n1 >= 5) n1 = n1 + 3;
                if (n2 >= 5) n2 = n2 + 3;
                n2 = {n2[2:0], n1[3]};
                n1 = {n1[2:0], n0[3]};
                n0 = {n0[2:0], src[7]};
                src = {src[6:0], 1'b0};
            end
            bcd8 = {n2, n1, n0};
        end
    endfunction

    wire [11:0] vol_bcd = bcd8(volume);
    wire [3:0] prd_tens =
        (period_sec >= 50) ? 4'd5 : (period_sec >= 40) ? 4'd4 :
        (period_sec >= 30) ? 4'd3 : (period_sec >= 20) ? 4'd2 :
        (period_sec >= 10) ? 4'd1 : 4'd0;
    wire [3:0] prd_ones =
        (period_sec >= 50) ? (period_sec - 6'd50) :
        (period_sec >= 40) ? (period_sec - 6'd40) :
        (period_sec >= 30) ? (period_sec - 6'd30) :
        (period_sec >= 20) ? (period_sec - 6'd20) :
        (period_sec >= 10) ? (period_sec - 6'd10) : {2'b0, period_sec[3:0]};

    // Active-high seven-segment font, bit0=A ... bit6=G.
    function [6:0] seg_font;
        input [4:0] sym;
        begin
            case (sym)
                5'd0:    seg_font = 7'h3f;
                5'd1:    seg_font = 7'h06;
                5'd2:    seg_font = 7'h5b;
                5'd3:    seg_font = 7'h4f;
                5'd4:    seg_font = 7'h66;
                5'd5:    seg_font = 7'h6d;
                5'd6:    seg_font = 7'h7d;
                5'd7:    seg_font = 7'h07;
                5'd8:    seg_font = 7'h7f;
                5'd9:    seg_font = 7'h6f;
                5'h10:   seg_font = 7'h00;  // blank
                5'h11:   seg_font = 7'h73;  // P
                5'h12:   seg_font = 7'h06;  // I
                5'h13:   seg_font = 7'h39;  // C
                5'h14:   seg_font = 7'h3e;  // V
                5'h15:   seg_font = 7'h38;  // L
                5'h18:   seg_font = 7'h6d;  // S
                5'h19:   seg_font = 7'h40;  // -
                default: seg_font = 7'h00;
            endcase
        end
    endfunction

    localparam [4:0] F_BLANK = 5'h10;
    localparam [4:0] F_P     = 5'h11;
    localparam [4:0] F_I     = 5'h12;
    localparam [4:0] F_C     = 5'h13;
    localparam [4:0] F_V     = 5'h14;
    localparam [4:0] F_L     = 5'h15;
    localparam [4:0] F_S     = 5'h18;
    localparam [4:0] F_DASH  = 5'h19;

    // symbols[0]..symbols[5] map to physical connected digits left-to-right.
    reg [4:0] symbols [0:5];
    integer d;
    always @* begin
        for (d = 0; d < 6; d = d + 1)
            symbols[d] = F_BLANK;
        case (page)
            PAGE_PIC: begin
                symbols[0] = F_P;
                symbols[1] = F_I;
                symbols[2] = F_C;
                symbols[5] = {1'b0, media_id} + 5'd1;
            end
            PAGE_VOL: begin
                symbols[0] = F_V;
                symbols[1] = 5'd0;  // O shares the zero glyph
                symbols[2] = F_L;
                symbols[3] = {1'b0, vol_bcd[11:8]};
                symbols[4] = {1'b0, vol_bcd[7:4]};
                symbols[5] = {1'b0, vol_bcd[3:0]};
            end
            PAGE_PRD: begin
                symbols[0] = F_P;
                symbols[1] = F_DASH;
                symbols[2] = prd_tens;
                symbols[3] = prd_ones;
                symbols[4] = F_DASH;
                symbols[5] = F_S;
            end
            default: ;
        endcase
    end

    reg [2:0] scan_idx;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            scan_cnt <= 13'd0;
            scan_idx <= 3'd0;
            dig_n    <= 6'b111110;
            seg_n    <= 8'hff;
        end else if (!enable) begin
            dig_n <= 6'h3f;
            seg_n <= 8'hff;
        end else begin
            if (scan_cnt == SCAN_STEP_CYCLES - 1) begin
                scan_cnt <= 13'd0;
                scan_idx <= (scan_idx == 3'd5) ? 3'd0 : scan_idx + 1'b1;
            end else begin
                scan_cnt <= scan_cnt + 1'b1;
            end
            dig_n <= ~(6'b000001 << scan_idx);
            seg_n <= {1'b1, ~seg_font(symbols[scan_idx])};
        end
    end
endmodule
