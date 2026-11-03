`timescale 1ns/1ps

// =============================================================================

// frame_manager_4bank.v - 4-Bank Frame Buffer Manager

// Migrated from Michu to 720p RGB565

// Date: 2026-09-18

// =============================================================================

//

// 四Bank帧缓存管理器：管理4个独立Bank的角色和状态转换

//

// Bank状态：

//   IDLE    - 空闲，可分配为LOADING

//   LOADING - 正在从SD卡加载图片

//   READY   - 加载完成，等待显示

//   DISPLAY - 正在显示

//

// 状态转换：

//   IDLE → LOADING → READY → DISPLAY → READY

//

// Static four-image mode: once all banks are loaded, switching only changes the

// DISPLAY owner. The released bank returns to READY and is not rewritten, so

// manual switching does not introduce write/read SDRAM contention.

//

// Bank地址空间（720p RGB565）：

//   Bank 0: 0x00000000 - 0x000707FF (460,800 words)

//   Bank 1: 0x00070800 - 0x000E0FFF (460,800 words)

//   Bank 2: 0x000E1000 - 0x001517FF (460,800 words)

//   Bank 3: 0x00151800 - 0x001C1FFF (460,800 words)

// =============================================================================



`include "global_def.v"



module frame_manager_4bank (

    // System clock domain

    input  wire        sys_clk,

    input  wire        sys_rst_n,



    // Manual/Auto control

    input  wire        next_image_req,      // 手动切换到下一张图片

    input  wire        auto_play_enable,    // 自动轮播使能

    input  wire [31:0] auto_period_cycles,  // 自动轮播周期（系统时钟周期数）



    // Loader interface (sys_clk domain)

    input  wire [3:0]  bank_load_complete,  // 每个Bank加载完成标志

    input  wire [3:0]  bank_load_error,     // 每个Bank加载错误标志

    output reg  [1:0]  next_load_bank,      // 下一个要加载的Bank索引

    output reg         start_load,          // 启动加载脉冲



    // Video clock domain

    input  wire        video_clk,

    input  wire        video_rst_n,

    input  wire        bank_commit_trig,    // 消隐起始提交脉冲（de下降沿，帧尾）



    // Bank control outputs (video_clk domain)

    output reg  [1:0]  display_bank,        // 当前显示的Bank索引

    output reg         bank_switch_commit,  // Bank切换提交脉冲（bank_commit_trig时）



    // Bank state outputs (for debug)

    output wire [1:0]  bank0_state,

    output wire [1:0]  bank1_state,

    output wire [1:0]  bank2_state,

    output wire [1:0]  bank3_state,



    // Bank base addresses (combinational, for reader/loader)

    output wire [31:0] bank0_base_addr,

    output wire [31:0] bank1_base_addr,

    output wire [31:0] bank2_base_addr,

    output wire [31:0] bank3_base_addr

);



    // =========================================================================

    // Bank Base Addresses (constant, word-addressed)

    // =========================================================================

    assign bank0_base_addr = `BANK0_BASE;  // 0x00000000

    assign bank1_base_addr = `BANK1_BASE;  // 0x00070800

    assign bank2_base_addr = `BANK2_BASE;  // 0x000E1000

    assign bank3_base_addr = `BANK3_BASE;  // 0x00151800



    // =========================================================================

    // Bank State Registers (sys_clk domain)

    // =========================================================================

    reg [1:0] bank_state [0:3];  // 4个Bank的状态



    assign bank0_state = bank_state[0];

    assign bank1_state = bank_state[1];

    assign bank2_state = bank_state[2];

    assign bank3_state = bank_state[3];



    // =========================================================================

    // Auto Play Timer (sys_clk domain)

    // =========================================================================

    reg [31:0] auto_counter;

    reg        auto_trigger;



    always @(posedge sys_clk or negedge sys_rst_n) begin

        if (!sys_rst_n) begin

            auto_counter <= 32'd0;

            auto_trigger <= 1'b0;

        end else begin

            auto_trigger <= 1'b0;  // 单周期脉冲



            if (auto_play_enable) begin

                if (auto_counter >= auto_period_cycles - 1) begin

                    auto_counter <= 32'd0;

                    auto_trigger <= 1'b1;

                end else begin

                    auto_counter <= auto_counter + 32'd1;

                end

            end else begin

                auto_counter <= 32'd0;

            end

        end

    end



    // =========================================================================

    // Next Image Request (sys_clk domain)

    // =========================================================================

    reg [1:0] pending_display_bank;   // 下一个要显示的Bank

    reg       display_request_toggle; // Toggle信号用于CDC

    reg [1:0] prev_display_bank;      // 已确认显示Bank（sys域，round-robin基准）



    // 环形候选顺序：当前+1、+2、+3；2位加法自然按4回绕。

    wire [1:0] rr_next1 = prev_display_bank + 2'd1;

    wire [1:0] rr_next2 = prev_display_bank + 2'd2;

    wire [1:0] rr_next3 = prev_display_bank + 2'd3;



    // 合并手动和自动触发

    wire next_trigger = next_image_req | auto_trigger;



    always @(posedge sys_clk or negedge sys_rst_n) begin

        if (!sys_rst_n) begin

            pending_display_bank <= 2'd0;

            display_request_toggle <= 1'b0;

        end else if (next_trigger) begin

            // 从当前显示Bank的下一项开始环形搜索READY：+1→+2→+3。

            // 不再固定选择最低编号READY，保证全READY时0→1→2→3→0。

            if (bank_state[rr_next1] == `BANK_STATE_READY) begin

                pending_display_bank <= rr_next1;

                display_request_toggle <= ~display_request_toggle;

            end else if (bank_state[rr_next2] == `BANK_STATE_READY) begin

                pending_display_bank <= rr_next2;

                display_request_toggle <= ~display_request_toggle;

            end else if (bank_state[rr_next3] == `BANK_STATE_READY) begin

                pending_display_bank <= rr_next3;

                display_request_toggle <= ~display_request_toggle;

            end

            // 如果没有其他READY Bank，保持不变且不发toggle。

        end

    end



    // =========================================================================

    // Load Arbitration (combinational)

    // =========================================================================

    // any_loading: 当前是否有bank处于LOADING（读寄存器当前值）

    // first_idle_bank: 最低编号的IDLE bank

    // for循环内非阻塞赋值读旧值会导致同拍多bank同时进入LOADING，

    // 因此只允许 first_idle_bank 对应的分支启动加载。

    wire any_loading = (bank_state[0] == `BANK_STATE_LOADING) ||

                       (bank_state[1] == `BANK_STATE_LOADING) ||

                       (bank_state[2] == `BANK_STATE_LOADING) ||

                       (bank_state[3] == `BANK_STATE_LOADING);



    reg [1:0] first_idle_bank;

    reg       has_idle_bank;

    integer j;

    always @* begin

        first_idle_bank = 2'd0;

        has_idle_bank = 1'b0;

        // 从高到低扫描，最后赋值的是最低编号IDLE bank

        for (j = 3; j >= 0; j = j - 1) begin

            if (bank_state[j] == `BANK_STATE_IDLE) begin

                first_idle_bank = j;

                has_idle_bank = 1'b1;

            end

        end

    end



    // =========================================================================

    // Bank State Machine (sys_clk domain) — 唯一驱动bank_state的进程

    // =========================================================================

    // 注意：bank_state 只允许本进程驱动（TD禁止多进程驱动同一net）。

    // for循环只转换 IDLE/LOADING 状态的bank；ack回握手只转换

    // READY/DISPLAY 状态的bank——同一拍内目标不相交，合并后无写冲突。

    integer i;



    reg ack_sync1, ack_sync2;

    reg ack_seen_sys;



    // video_clk域寄存器（声明提前：iverilog要求先声明后使用）

    reg        req_toggle_sync1, req_toggle_sync2;

    reg        req_seen_video;

    reg [1:0]  pending_bank_sync1, pending_bank_sync2;

    reg [1:0]  requested_bank_video;

    reg        commit_pending;

    reg        ack_toggle_video;



    always @(posedge sys_clk or negedge sys_rst_n) begin

        if (!sys_rst_n) begin

            bank_state[0] <= `BANK_STATE_IDLE;

            bank_state[1] <= `BANK_STATE_IDLE;

            bank_state[2] <= `BANK_STATE_IDLE;

            bank_state[3] <= `BANK_STATE_IDLE;

            next_load_bank <= 2'd0;

            start_load <= 1'b0;

            ack_sync1 <= 1'b0;

            ack_sync2 <= 1'b0;

            ack_seen_sys <= 1'b0;

            prev_display_bank <= 2'd0;

        end else begin

            start_load <= 1'b0;  // 单周期脉冲



            // 2FF同步ack toggle（video→sys回握手）

            ack_sync1 <= ack_toggle_video;

            ack_sync2 <= ack_sync1;



            // 处理每个Bank的状态转换

            for (i = 0; i < 4; i = i + 1) begin

                case (bank_state[i])

                    `BANK_STATE_IDLE: begin

                        // 仅当无bank在LOADING且本bank是最低编号IDLE时启动

                        if (!any_loading && has_idle_bank &&

                            i == first_idle_bank) begin

                            // 启动加载（外部loader会响应start_load信号）

                            bank_state[i] <= `BANK_STATE_LOADING;

                            next_load_bank <= i[1:0];

                            start_load <= 1'b1;

                        end

                    end



                    `BANK_STATE_LOADING: begin

                        // 加载完成 → READY

                        if (bank_load_complete[i]) begin

                            bank_state[i] <= `BANK_STATE_READY;

                        end

                        // 加载错误 → IDLE（重试或跳过）

                        else if (bank_load_error[i]) begin

                            bank_state[i] <= `BANK_STATE_IDLE;

                        end

                    end



                    default: begin

                        // READY/DISPLAY：转换由下方ack回握手处理

                    end

                endcase

            end



            // 检测到ack变化：旧DISPLAY → READY，新READY → DISPLAY

            if (ack_sync2 != ack_seen_sys) begin

                ack_seen_sys <= ack_sync2;



                // 静态四图模式：旧显示Bank保留为READY，不重复写SDRAM。

                if (bank_state[prev_display_bank] == `BANK_STATE_DISPLAY) begin

                    bank_state[prev_display_bank] <= `BANK_STATE_READY;

                end



                // 新的display bank从READY变为DISPLAY

                // （pending_display_bank在sys_clk域，见上方手动/自动请求逻辑）

                if (bank_state[pending_display_bank] == `BANK_STATE_READY) begin

                    bank_state[pending_display_bank] <= `BANK_STATE_DISPLAY;

                end



                prev_display_bank <= pending_display_bank;

            end

        end

    end



    // =========================================================================

    // CDC: sys_clk → video_clk (display bank switch)

    // =========================================================================

    // 使用Toggle + 2FF同步（寄存器声明见上方状态机进程之前）



    // Video clock domain: 同步toggle信号

    always @(posedge video_clk or negedge video_rst_n) begin

        if (!video_rst_n) begin

            req_toggle_sync1 <= 1'b0;

            req_toggle_sync2 <= 1'b0;

            pending_bank_sync1 <= 2'd0;

            pending_bank_sync2 <= 2'd0;

            req_seen_video <= 1'b0;

            requested_bank_video <= 2'd0;

            commit_pending <= 1'b0;

            display_bank <= 2'd0;

            bank_switch_commit <= 1'b0;

            ack_toggle_video <= 1'b0;

        end else begin

            // 2FF同步toggle和bank index

            req_toggle_sync1 <= display_request_toggle;

            req_toggle_sync2 <= req_toggle_sync1;

            pending_bank_sync1 <= pending_display_bank;

            pending_bank_sync2 <= pending_bank_sync1;



            bank_switch_commit <= 1'b0;  // 单周期脉冲



            // 检测到新的请求

            if (req_toggle_sync2 != req_seen_video && !commit_pending) begin

                req_seen_video <= req_toggle_sync2;

                requested_bank_video <= pending_bank_sync2;

                commit_pending <= 1'b1;

            end



            // 在消隐起始（帧尾）提交切换——reader在同一frame_boundary后

            // 延迟64拍再锁存display_bank，因此这里的非阻塞更新可稳定传递。

            if (bank_commit_trig && commit_pending) begin

                display_bank <= requested_bank_video;

                bank_switch_commit <= 1'b1;

                commit_pending <= 1'b0;

                ack_toggle_video <= req_seen_video;

            end

        end

    end



    // =========================================================================

    // CDC: video_clk → sys_clk (ack) — 同步寄存器已合并进上方唯一状态机进程

    // =========================================================================



endmodule

