// One-entry registered PCM boundary. The upstream ready depends only on local
// state, intentionally inserting a refill bubble to break the FIFO-full to
// WAV/file/sector combinational path.
module m9_pcm_skid_buffer (
    input wire clk,input wire rst,input wire clear,
    input wire in_valid,output wire in_ready,
    input wire signed [15:0] in_data,input wire in_last,
    output wire out_valid,input wire out_ready,
    output wire signed [15:0] out_data,output wire out_last
);
    reg held_valid;
    reg signed [15:0] held_data;
    reg held_last;

    assign in_ready=!held_valid;
    assign out_valid=held_valid;
    assign out_data=held_data;
    assign out_last=held_last;

    always @(posedge clk or posedge rst) begin
        if(rst) begin
            held_valid<=1'b0;
            held_data<=16'sd0;
            held_last<=1'b0;
        end else if(clear) begin
            held_valid<=1'b0;
            held_data<=16'sd0;
            held_last<=1'b0;
        end else if(held_valid) begin
            if(out_ready) held_valid<=1'b0;
        end else if(in_valid) begin
            held_valid<=1'b1;
            held_data<=in_data;
            held_last<=in_last;
        end
    end
endmodule
