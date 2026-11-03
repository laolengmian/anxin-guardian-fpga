`timescale 1ns/1ps
module m9_final_level_control (
    input wire clk,input wire rst,
    input wire brightness_up,input wire brightness_down,
    input wire volume_up,input wire volume_down,
    output reg [3:0] brightness_level,output reg [3:0] volume_level,
    output reg brightness_update,output reg volume_update
);
    wire brightness_cancel=brightness_up && brightness_down;
    wire volume_cancel=volume_up && volume_down;
    always @(posedge clk or posedge rst) begin
        if(rst) begin
            brightness_level<=4;volume_level<=4;
            brightness_update<=0;volume_update<=0;
        end else begin
            brightness_update<=0;volume_update<=0;
            if(!brightness_cancel && brightness_up && brightness_level<8) begin
                brightness_level<=brightness_level+1'b1;brightness_update<=1'b1;
            end else if(!brightness_cancel && brightness_down && brightness_level>0) begin
                brightness_level<=brightness_level-1'b1;brightness_update<=1'b1;
            end
            if(!volume_cancel && volume_up && volume_level<8) begin
                volume_level<=volume_level+1'b1;volume_update<=1'b1;
            end else if(!volume_cancel && volume_down && volume_level>0) begin
                volume_level<=volume_level-1'b1;volume_update<=1'b1;
            end
        end
    end
endmodule
