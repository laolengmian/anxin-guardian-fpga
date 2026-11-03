`timescale 1ns / 1ps

// =============================================================================

// video_timing_ctrl.v - Video Timing Controller for 720p@60Hz

// Migrated from Michu 480p to our 720p RGB565

// Date: 2026-09-18

// =============================================================================

//

// 视频时序控制器：像素时钟域内的行/场计数器加同拍组合译码

//

// 输出信号：

//   x/y      : 行/场计数器，0..H_TOTAL-1 / 0..V_TOTAL-1；de=1时为有效像素坐标

//   de       : 有效显示区标志，(x < H_ACT) && (y < V_ACT)

//   hsync    : 低有效行同步脉冲

//   vsync    : 低有效场同步脉冲

//   frame_start : 帧起始脉冲（x=0 && y=0）

//   line_end    : 行结束脉冲（x=H_TOTAL-1）

//

// 720p@60.606Hz时序参数（默认）

// =============================================================================



`include "global_def.v"



module video_timing_ctrl #(

    parameter H_ACT  = `H_ACTIVE,   // 1280 - 水平有效像素

    parameter H_FP   = `H_FP,       // 110  - 水平前肩

    parameter H_SYNC = `H_SYNC,     // 40   - 水平同步脉宽

    parameter H_BP   = `H_BP,       // 220  - 水平后肩

    parameter V_ACT  = `V_ACTIVE,   // 720  - 垂直有效行

    parameter V_FP   = `V_FP,       // 5    - 垂直前肩

    parameter V_SYNC = `V_SYNC,     // 5    - 垂直同步脉宽

    parameter V_BP   = `V_BP,       // 20   - 垂直后肩

    parameter ACTIVE_LAST = 0       // 0=Active在前，1=Active在后（保留米处兼容性）

)(

    input  wire        pclk,        // 像素时钟（75 MHz for 720p@60.606Hz）

    input  wire        rst_n,       // 低有效复位

    output wire        hsync,       // 低有效行同步

    output wire        vsync,       // 低有效场同步

    output wire        de,          // 有效显示区

    output reg  [11:0] x,           // 行计数器（0..1649）

    output reg  [11:0] y,           // 场计数器（0..749）

    output wire        frame_start, // 帧起始脉冲

    output wire        line_end     // 行结束脉冲

);



    // 计算总时序

    localparam H_TOTAL = H_ACT + H_FP + H_SYNC + H_BP;  // 1280+110+40+220 = 1650

    localparam V_TOTAL = V_ACT + V_FP + V_SYNC + V_BP;  // 720+5+5+20 = 750



    // 帧率验证（仿真时打印）

    // 1650 × 750 × 60 = 74.25 MHz

    // 实际PLL输出75MHz，误差：(75-74.25)/74.25 = 1.01% ✓



    // =========================================================================

    // 行/场计数器

    // =========================================================================

    // x走完一行，y走一步；两个都走完回到帧起点(0,0)

    always @(posedge pclk or negedge rst_n) begin

        if (!rst_n) begin

            x <= 12'd0;

            y <= 12'd0;

        end else if (x == H_TOTAL - 1) begin

            x <= 12'd0;

            y <= (y == V_TOTAL - 1) ? 12'd0 : y + 12'd1;

        end else begin

            x <= x + 12'd1;

        end

    end



    // =========================================================================

    // 同拍组合译码（与x/y永远对齐）

    // =========================================================================



    // 有效显示区

    assign de = ACTIVE_LAST ?

                ((x >= H_TOTAL - H_ACT) && (y >= V_TOTAL - V_ACT)) :

                ((x < H_ACT) && (y < V_ACT));



    // 行同步（低有效）

    assign hsync = ACTIVE_LAST ?

                   ~((x >= H_FP) && (x < H_FP + H_SYNC)) :

                   ~((x >= H_ACT + H_FP) && (x < H_ACT + H_FP + H_SYNC));



    // 场同步（低有效）

    assign vsync = ACTIVE_LAST ?

                   ~((y >= V_FP) && (y < V_FP + V_SYNC)) :

                   ~((y >= V_ACT + V_FP) && (y < V_ACT + V_FP + V_SYNC));



    // =========================================================================

    // 帧边界和行边界标志（用于四Bank控制器）

    // =========================================================================



    // 帧起始：x=0 && y=0（新帧开始）

    assign frame_start = (x == 12'd0) && (y == 12'd0);



    // 行结束：x=H_TOTAL-1（当前行最后一个像素）

    assign line_end = (x == H_TOTAL - 1);



endmodule

