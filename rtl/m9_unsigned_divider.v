`timescale 1ns/1ps
// Restoring unsigned division: WIDTH clocks, no combinational divide operator.
module m9_unsigned_divider #(parameter integer WIDTH=48)(
    input wire clk,input wire rst,input wire start,
    input wire [WIDTH-1:0] numerator,input wire [WIDTH-1:0] denominator,
    output reg busy,output reg done,output reg divide_by_zero,
    output reg [WIDTH-1:0] quotient
);
    reg [WIDTH-1:0] q,divisor;
    reg [WIDTH:0] remainder;
    integer remaining;
    wire [WIDTH:0] shifted={remainder[WIDTH-1:0],q[WIDTH-1]};
    wire subtract=shifted>={1'b0,divisor};
    wire [WIDTH-1:0] next_q={q[WIDTH-2:0],subtract};
    always @(posedge clk) begin
        if(rst) begin
            q<=0;divisor<=0;remainder<=0;remaining<=0;
            busy<=0;done<=0;divide_by_zero<=0;quotient<=0;
        end else begin
            done<=0;
            if(start && !busy) begin
                divide_by_zero<=denominator==0;
                if(denominator==0) begin quotient<=0;done<=1;end
                else begin
                    q<=numerator;divisor<=denominator;remainder<=0;
                    remaining<=WIDTH;busy<=1;
                end
            end else if(busy) begin
                remainder<=subtract ? shifted-{1'b0,divisor} : shifted;
                q<=next_q;remaining<=remaining-1;
                if(remaining==1) begin quotient<=next_q;busy<=0;done<=1;end
            end
        end
    end
endmodule
