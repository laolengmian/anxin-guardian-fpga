// For the M9 one-cycle word producer only, NOT a retryable valid/ready stream.
// Full with no write pulse is legal backpressure; a rejected pulse loses a word.
module m9_write_loss_monitor (
    input wire clk,input wire rst,
    input wire write_pulse,input wire write_ready,input wire media_busy,
    output reg overflow_sticky,output reg write_expected
);
    always @(posedge clk or posedge rst) begin
        if(rst) overflow_sticky<=1'b0;
        else if(write_pulse && !write_ready) overflow_sticky<=1'b1;
    end
    always @(posedge clk or posedge rst) begin
        if(rst) write_expected<=1'b0;
        else write_expected<=media_busy || overflow_sticky;
    end
endmodule
