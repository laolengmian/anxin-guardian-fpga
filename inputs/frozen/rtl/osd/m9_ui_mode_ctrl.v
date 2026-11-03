`timescale 1ns/1ps

// Display-only SW3 input in the video clock domain. The frame mode samples
// the old accepted value when qualification and frame_first coincide.
module m9_ui_mode_ctrl #(
    parameter integer STABLE_CYCLES=375000
) (
    input wire clk,input wire rst,
    input wire sw_diagnostic_async,input wire frame_first,
    output reg diagnostic_requested,output reg diagnostic_active
);
    localparam integer COUNT_BITS=STABLE_CYCLES<=1 ? 1 : $clog2(STABLE_CYCLES);
    localparam [COUNT_BITS-1:0] STABLE_LAST=STABLE_CYCLES-1;
    reg mode_sync1,mode_sync2;
    reg [COUNT_BITS-1:0] stable_count;

    initial begin
        if(STABLE_CYCLES<1) begin
            $display("M9_UI_MODE_CONFIG_ERROR STABLE_CYCLES must be positive");
            $finish;
        end
    end

    always @(posedge clk or posedge rst) begin
        if(rst) begin
            mode_sync1<=1'b0;
            mode_sync2<=1'b0;
        end else begin
            mode_sync1<=sw_diagnostic_async;
            mode_sync2<=mode_sync1;
        end
    end

    always @(posedge clk or posedge rst) begin
        if(rst) begin
            stable_count<=0;
            diagnostic_requested<=1'b0;
            diagnostic_active<=1'b0;
        end else begin
            if(mode_sync2==diagnostic_requested)
                stable_count<=0;
            else if(stable_count==STABLE_LAST) begin
                stable_count<=0;
                diagnostic_requested<=mode_sync2;
            end else
                stable_count<=stable_count+1'b1;

            if(frame_first)
                diagnostic_active<=diagnostic_requested;
        end
    end
endmodule
