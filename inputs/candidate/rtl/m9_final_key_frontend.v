`timescale 1ns/1ps
// Six independent active-low keys. Each channel has its own 2FF, debounce
// counter, release qualification, and one-shot; no short/long-press decoding.
module m9_final_key_frontend #(
    parameter integer STABLE_CYCLES = 1000000
) (
    input wire clk,input wire rst,input wire [5:0] key_n_async,
    output reg [5:0] press_pulse,output reg [5:0] stable_pressed
);
    localparam integer COUNT_WIDTH =
        (STABLE_CYCLES <= 1) ? 1 : $clog2(STABLE_CYCLES);
    (* ASYNC_REG = "TRUE" *) reg [5:0] sync_stage1,sync_stage2;
    reg [5:0] stable_n,released_once;
    reg [COUNT_WIDTH-1:0] count [0:5];
    reg [COUNT_WIDTH-1:0] release_count [0:5];
    integer index;
    initial if(STABLE_CYCLES<3) begin
        $display("M9_FINAL_KEY_CONFIG_ERROR STABLE_CYCLES must be at least 3");
        $finish;
    end
    always @(posedge clk or posedge rst) begin
        if(rst) begin
            sync_stage1<=6'b111111;sync_stage2<=6'b111111;
            stable_n<=6'b111111;stable_pressed<=0;press_pulse<=0;
            released_once<=0;
            for(index=0;index<6;index=index+1) begin
                count[index]<=0;release_count[index]<=0;
            end
        end else begin
            sync_stage1<=key_n_async;sync_stage2<=sync_stage1;
            press_pulse<=0;
            for(index=0;index<6;index=index+1) begin
                if(sync_stage2[index]===stable_n[index])
                    count[index]<=0;
                else if((sync_stage2[index]===1'b0 || sync_stage2[index]===1'b1) &&
                        count[index]==STABLE_CYCLES-1) begin
                    count[index]<=0;
                    stable_n[index]<=sync_stage2[index];
                    stable_pressed[index]<=!sync_stage2[index];
                    if(!sync_stage2[index] && released_once[index]) begin
                        press_pulse[index]<=1'b1;
                        released_once[index]<=1'b0;
                    end
                end else if(sync_stage2[index]===1'b0 || sync_stage2[index]===1'b1)
                    count[index]<=count[index]+1'b1;
                else
                    count[index]<=0;
                // Count consecutive synchronized highs independently of the
                // debounced state, including channels already high at reset.
                // Only this full interval arms a subsequent press.
                if(sync_stage2[index]===1'b1 && !released_once[index]) begin
                    if(release_count[index]==STABLE_CYCLES-1) begin
                        release_count[index]<=0;released_once[index]<=1'b1;
                    end else
                        release_count[index]<=release_count[index]+1'b1;
                end else
                    release_count[index]<=0;
            end
        end
    end
endmodule
