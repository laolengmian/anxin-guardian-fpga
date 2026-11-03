`timescale 1ns/1ps
// One sample-boundary gain stage, no multiplier/DSP. Level 4 is unity and
// level 0 is mute. Invalid cycles preserve both PCM channels. Gain slews
// by one table step per valid sample, so a key event cannot jump directly
// from unity to 2.5x or mute; sample-valid cadence is unchanged.
module m9_pcm_volume (
    input wire clk,input wire rst,input wire in_valid,
    input wire [23:0] in_left,input wire [23:0] in_right,
    input wire [3:0] level,input wire level_update,
    output reg out_valid,output reg [23:0] out_left,output reg [23:0] out_right
);
    reg [3:0] current_level,target_level;

    function [23:0] scaled;
        input [23:0] sample;input [3:0] gain_level;
        reg signed [24:0] extended;
        reg signed [27:0] numerator;
        reg signed [27:0] quotient;
        begin
            extended=$signed({sample[23],sample});
            case(gain_level)
                0:numerator=0;
                1:numerator=extended;
                2:numerator=extended<<<1;
                3:numerator=extended+(extended<<<1);
                5:numerator=extended+(extended<<<2);
                6:numerator=(extended<<<1)+(extended<<<2);
                7:numerator=extended<<<3;
                8:numerator=(extended<<<3)+(extended<<<1);
                default:numerator=extended<<<2;
            endcase
            quotient=numerator>>>2;
            if(quotient>28'sd8388607)scaled=24'h7fffff;
            else if(quotient< -28'sd8388608)scaled=24'h800000;
            else scaled=quotient[23:0];
        end
    endfunction
    always @(posedge clk or posedge rst) begin
        if(rst) begin
            out_valid<=0;out_left<=0;out_right<=0;
            current_level<=4;target_level<=4;
        end else begin
            out_valid<=in_valid;
            if(level_update) target_level<=(level<=8) ? level : 4;
            if(in_valid) begin
                out_left<=scaled(in_left,current_level);
                out_right<=scaled(in_right,current_level);
                if(current_level<target_level) current_level<=current_level+1'b1;
                else if(current_level>target_level) current_level<=current_level-1'b1;
            end
        end
    end
endmodule
