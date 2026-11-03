`timescale 1ns/1ps

// Nine-level M6-A-compatible brightness law with a single cyclic advance event.
// Shift/add only; no multiplier or DSP.
module m6c_brightness_cycle (
    input  wire clk,
    input  wire rst,
    input  wire advance_event,
    output reg  [3:0] level,
    output wire signed [8:0] offset
);
    wire [9:0] dim_scaled = {1'b0, level, 5'b00000} - 10'd128;
    wire [9:0] bright_scaled = {2'b00, level, 4'b0000} - 10'd64;

    assign offset = level > 4'd4 ? bright_scaled[8:0] : dim_scaled[8:0];

    always @(posedge clk or posedge rst) begin
        if (rst)
            level <= 4'd4;
        else if (advance_event)
            level <= level == 4'd8 ? 4'd0 : level + 1'b1;
    end
endmodule
