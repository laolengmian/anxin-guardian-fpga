`timescale 1ns/1ps
// =============================================================================
// frame_loader_4bank_v2.v - Write-side master for official frame_read_write
// Date: 2026-09-18
// =============================================================================
//
// 替代 frame_loader_4bank 的SDRAM接口：对接官方 frame_read_write 写侧
// （帧级 req/ack + word级 write_en + 4bank基址 + write_finish）。
//
// 协议要点（官方 frame_fifo_write 源码精读结论）：
//   1. write_req 拉高保持，直到看到 write_req_ack=1（本域同步后）才撤req；
//   2. ack=1 期间官方FSM处于S_ACK，内部wfifo的aclr=1（正在清FIFO）——
//      此时流数据会被清掉！必须等 ack 回落（=已进S_CHECK_FIFO）才能
//      开始 write_en 流；
//   3. write_en 每word拉1拍直推512深wfifo，无流控（平均速率低于
//      SDRAM侧125MHz排空速率即可，460800词@50M词/s << 85M词/s）；
//   4. write_len 个词写完且req已撤时，官方脉冲 write_finish（单拍）；
//   5. ack/finish 位于 mem_clk(125M) 域，本模块2FF同步后使用。
//
// 像素约定：word[15:0]=偶数像素，word[31:16]=奇数像素（与v1一致）。
// 看门狗：STREAM态超过~1.3s无任何像素 → load_error(ERR_SRC_STALL)。
// =============================================================================

module frame_loader_4bank_v2 #(
    parameter integer WORDS_PER_FRAME  = 460800,  // 1280*720/2，仿真可覆盖小值
    parameter integer STREAM_BURST_WORDS = 256,   // 连续流256词后暂停（=官方BURST_SIZE）
    parameter integer STREAM_GAP_CYCLES  = 768    // 暂停拍数：写占空比约25%，
                                                  // 给显示读侧留SDRAM带宽，防rfifo欠载
) (
    input  wire        clk,              // = write_clk（sys域100M）
    input  wire        rst_n,

    // frame_manager 控制接口（sys域，兼容v1语义）
    input  wire [1:0]  load_bank_index,
    input  wire        load_start,       // 单拍脉冲
    output reg         load_complete,    // 单拍脉冲
    output reg         load_error,       // 单拍脉冲
    output reg  [7:0]  error_code,
    output reg  [1:0]  load_bank_active, // 最近一次加载的bank（供顶层按位分发complete/error）

    // 像素源（拉模型，同域）
    output reg         pix_req,
    output wire        pix_rst,          // 帧中止复位（空闲/出错时拉高，暂停不拉）
    input  wire        pix_valid,
    input  wire [23:0] pix_rgb888,

    // 官方 frame_read_write 写侧
    output reg         write_req,
    input  wire        write_req_ack,    // mem_clk域
    output wire        write_en,
    output wire [31:0] write_data,
    input  wire        write_finish,     // mem_clk域
    output wire [20:0] write_addr_0,
    output wire [20:0] write_addr_1,
    output wire [20:0] write_addr_2,
    output wire [20:0] write_addr_3,
    output wire [1:0]  write_addr_index,
    output wire [20:0] write_len
);

    // -------------------------------------------------------------------------
    // 状态机
    // -------------------------------------------------------------------------
    localparam S_IDLE         = 3'd0;
    localparam S_REQ          = 3'd1;   // write_req=1，等ack
    localparam S_WAIT_ACK_LOW = 3'd2;   // 已见ack并撤req，等ack回落
    localparam S_STREAM       = 3'd3;   // 拉像素流、打包、write_en
    localparam S_WAIT_FINISH  = 3'd4;   // 等官方write_finish脉冲
    localparam S_DONE         = 3'd5;   // load_complete脉冲
    localparam S_ERROR        = 3'd6;   // load_error脉冲
    localparam S_GAP          = 3'd7;   // 突发间暂停（让出SDRAM读带宽）

    localparam [7:0] ERR_SRC_STALL = 8'h31;  // ERR_SDRAM_LOAD_BASE+1: 像素源停滞

    reg [2:0]  state;
    reg [1:0]  bank_r;
    reg        pix_phase;      // 0=收偶数像素 1=收奇数像素
    reg [15:0] even_pix565;    // 偶数像素缓存（已转RGB565）
    reg [31:0] word_cnt;
    reg [8:0]  burst_words;    // 当前突发已写词数
    reg [10:0] gap_cnt;        // 暂停计数

    // -------------------------------------------------------------------------
    // ack / finish 的2FF同步（mem_clk -> clk）
    // -------------------------------------------------------------------------
    reg ack_sync1, ack_sync2;
    reg fin_sync1, fin_sync2;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ack_sync1 <= 1'b0; ack_sync2 <= 1'b0;
            fin_sync1 <= 1'b0; fin_sync2 <= 1'b0;
        end else begin
            ack_sync1 <= write_req_ack;
            ack_sync2 <= ack_sync1;
            fin_sync1 <= write_finish;
            fin_sync2 <= fin_sync1;
        end
    end

    // -------------------------------------------------------------------------
    // RGB888 -> RGB565（同v1）
    // -------------------------------------------------------------------------
    function [15:0] rgb888_to_rgb565;
        input [23:0] rgb888;
        begin
            rgb888_to_rgb565 = {rgb888[23:19], rgb888[15:10], rgb888[7:3]};
        end
    endfunction

    // -------------------------------------------------------------------------
    // 打包与看门狗
    // -------------------------------------------------------------------------
    wire stream_word = (state == S_STREAM) && pix_valid && pix_phase;
    wire word_last   = (word_cnt == WORDS_PER_FRAME[31:0] - 32'd1);

    reg [26:0] stall_cnt;   // 2^27 cycles @100M ≈ 1.34s
    wire stall_timeout = (stall_cnt == 27'd134_000_000);

    // -------------------------------------------------------------------------
    // 主状态机
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state            <= S_IDLE;
            bank_r           <= 2'd0;
            pix_phase        <= 1'b0;
            even_pix565      <= 16'd0;
            word_cnt         <= 32'd0;
            load_complete    <= 1'b0;
            load_error       <= 1'b0;
            error_code       <= 8'h00;
            load_bank_active <= 2'd0;
            pix_req          <= 1'b0;
            write_req        <= 1'b0;
            stall_cnt        <= 27'd0;
        end else begin
            load_complete <= 1'b0;
            load_error    <= 1'b0;

            case (state)
                S_IDLE: begin
                    if (load_start) begin
                        bank_r           <= load_bank_index;
                        load_bank_active <= load_bank_index;
                        write_req        <= 1'b1;
                        word_cnt         <= 32'd0;
                        pix_phase        <= 1'b0;
                        burst_words      <= 9'd0;
                        stall_cnt        <= 27'd0;
                        state            <= S_REQ;
                    end
                end

                S_REQ: begin
                    // 官方在mem_clk域3FF同步req后置ack；看到同步ack=1才撤req
                    if (ack_sync2) begin
                        write_req <= 1'b0;
                        state     <= S_WAIT_ACK_LOW;
                    end
                end

                S_WAIT_ACK_LOW: begin
                    // ack回落 = 官方FSM已离开S_ACK，fifo_aclr已撤销，可安全流数据
                    if (!ack_sync2) begin
                        pix_req   <= 1'b1;
                        pix_phase <= 1'b0;
                        stall_cnt <= 27'd0;
                        state     <= S_STREAM;
                    end
                end

                S_STREAM: begin
                    if (pix_valid) begin
                        stall_cnt <= 27'd0;
                        if (!pix_phase) begin
                            // 偶数像素：缓存
                            even_pix565 <= rgb888_to_rgb565(pix_rgb888);
                            pix_phase   <= 1'b1;
                        end else if (word_last) begin
                            // 最后一个词：直接收尾
                            pix_req <= 1'b0;
                            state   <= S_WAIT_FINISH;
                        end else begin
                            pix_phase <= 1'b0;
                            word_cnt  <= word_cnt + 32'd1;
                            if (burst_words == STREAM_BURST_WORDS[8:0] - 9'd1) begin
                                // 突发写满：暂停，让出SDRAM给显示读侧
                                burst_words <= 9'd0;
                                pix_req     <= 1'b0;   // 像素源冻结可续
                                gap_cnt     <= 11'd0;
                                state       <= S_GAP;
                            end else begin
                                burst_words <= burst_words + 9'd1;
                            end
                        end
                    end else if (stall_timeout) begin
                        pix_req    <= 1'b0;
                        error_code <= ERR_SRC_STALL;
                        state      <= S_ERROR;
                    end else begin
                        stall_cnt <= stall_cnt + 27'd1;
                    end
                end

                S_GAP: begin
                    // 吸收pattern在途的1拍pix_valid（撤pix_req时的残留），
                    // 作为下一word的偶像素，否则每GAP漏1px、整帧少9word
                    if (pix_valid) begin
                        even_pix565 <= rgb888_to_rgb565(pix_rgb888);
                        pix_phase   <= 1'b1;
                        stall_cnt   <= 27'd0;
                    end
                    if (gap_cnt >= STREAM_GAP_CYCLES[10:0] - 11'd1) begin
                        pix_req <= 1'b1;   // 像素源从冻结点继续
                        state   <= S_STREAM;
                    end else begin
                        gap_cnt <= gap_cnt + 11'd1;
                    end
                end

                S_WAIT_FINISH: begin
                    if (fin_sync2) begin
                        state <= S_DONE;
                    end else if (stall_timeout) begin
                        // 官方write_finish迟迟不来（>1.3s）——按错误处理防死等
                        error_code <= 8'h32;   // ERR_WRITE_FINISH_TIMEOUT
                        state      <= S_ERROR;
                    end else begin
                        stall_cnt <= stall_cnt + 27'd1;
                    end
                end

                S_DONE: begin
                    load_complete <= 1'b1;
                    error_code    <= 8'h00;
                    state         <= S_IDLE;
                end

                S_ERROR: begin
                    load_error <= 1'b1;
                    state      <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

    // -------------------------------------------------------------------------
    // 写通道输出（组合）
    // -------------------------------------------------------------------------
    assign write_en   = stream_word;
    assign write_data = {rgb888_to_rgb565(pix_rgb888), even_pix565};

    // 帧中止时复位像素源（S_GAP暂停期间保持0，续流位置不丢）
    assign pix_rst = (state == S_IDLE) || (state == S_ERROR);

    // 4个bank基址常量（word地址，与global_def一致）
    assign write_addr_0 = 21'h000000;
    assign write_addr_1 = 21'h070800;
    assign write_addr_2 = 21'h0E1000;
    assign write_addr_3 = 21'h151800;
    assign write_addr_index = bank_r;
    assign write_len = WORDS_PER_FRAME[20:0];

endmodule
