`timescale 1ns/1ps
// Radix-four restoring floor(sqrt(value)), 16 processing clocks.
module m9_integer_sqrt(
    input wire clk,input wire rst,input wire start,input wire [31:0] value,
    output reg busy,output reg done,output reg [15:0] result
);
    reg [31:0] operand;
    reg [33:0] remainder;
    reg [15:0] root;
    reg [4:0] remaining;
    wire [33:0] shifted={remainder[31:0],operand[31:30]};
    wire [33:0] trial={16'd0,root,2'b01};
    wire take=shifted>=trial;
    wire [15:0] next_root={root[14:0],take};
    always @(posedge clk) begin
        if(rst) begin operand<=0;remainder<=0;root<=0;remaining<=0;busy<=0;done<=0;result<=0;end
        else begin
            done<=0;
            if(start && !busy) begin
                operand<=value;remainder<=0;root<=0;remaining<=16;busy<=1;
            end else if(busy) begin
                operand<=operand<<2;remainder<=take ? shifted-trial : shifted;
                root<=next_root;remaining<=remaining-1'b1;
                if(remaining==1) begin result<=next_root;busy<=0;done<=1;end
            end
        end
    end
endmodule
