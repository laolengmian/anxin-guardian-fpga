// Final common mute point for HDMI audio and the on-screen Audio Monitor.
// The M8 mixer already registers its samples, so a second 48-bit holding bank
// is unnecessary. The current synchronized SAFE level masks both channels in
// the same cycle and preserves the original valid cadence.
module m9_audio_safe_gate (
    input wire clk,input wire rst,input wire in_valid,
    input wire [23:0] in_left,input wire [23:0] in_right,
    input wire safe_pause,
    output wire out_valid,
    output wire [23:0] out_left,
    output wire [23:0] out_right
);
    wire muted=safe_pause || rst;
    assign out_valid=in_valid && !rst;
    assign out_left=muted ? 24'd0 : in_left;
    assign out_right=muted ? 24'd0 : in_right;
endmodule
