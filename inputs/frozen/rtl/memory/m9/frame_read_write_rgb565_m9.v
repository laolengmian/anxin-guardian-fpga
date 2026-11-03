module frame_read_write_rgb565_m9 #(
    parameter integer MEM_DATA_BITS = 32,
    parameter integer ADDR_BITS = 21,
    parameter integer BURST_BITS = 9,
    parameter integer FIFO_DEPTH = 512,
    parameter integer BURST_SIZE = 256,
    parameter integer WRITE_V_FLIP = 0,
    parameter integer WRITE_PACE_DIV = 16,
    parameter integer FRAME_WIDTH = 640,
    parameter integer FRAME_HEIGHT = 720,
    parameter integer READ_BURST_IDLE_GUARD = 0,
    parameter integer READ_BURST_REFRESH_BUDGET = 0,
    parameter integer WRITE_BURST_REFRESH_BUDGET = 0
) (
    input wire rst,
    input wire mem_clk,
    input wire Sdr_init_done,
    input wire Sdr_init_ref_vld,
    input wire Sdr_busy,
    output wire App_rd_en,
    output wire [ADDR_BITS-1:0] App_rd_addr,
    input wire Sdr_rd_en,
    input wire [MEM_DATA_BITS-1:0] Sdr_rd_dout,

    input wire read_clk,
    input wire read_req,
    output wire read_req_ack,
    output wire read_finish,
    input wire [ADDR_BITS-1:0] read_addr_0,
    input wire [ADDR_BITS-1:0] read_addr_1,
    input wire [ADDR_BITS-1:0] read_addr_2,
    input wire [ADDR_BITS-1:0] read_addr_3,
    input wire [1:0] read_addr_index,
    input wire [ADDR_BITS-1:0] read_len,
    input wire read_pop,
    output wire [31:0] read_data,
    output wire read_valid,
    output wire read_empty,
    output wire [9:0] read_level,
    input wire clear_read_faults,
    output wire read_underflow_sticky,

    output wire App_wr_en,
    output wire [ADDR_BITS-1:0] App_wr_addr,
    output wire [MEM_DATA_BITS-1:0] App_wr_din,
    output wire [3:0] App_wr_dm,

    input wire write_clk,
    input wire write_req,
    output wire write_req_ack,
    output wire write_finish,
    input wire [ADDR_BITS-1:0] write_addr_0,
    input wire [ADDR_BITS-1:0] write_addr_1,
    input wire [ADDR_BITS-1:0] write_addr_2,
    input wire [ADDR_BITS-1:0] write_addr_3,
    input wire [1:0] write_addr_index,
    input wire [ADDR_BITS-1:0] write_len,
    input wire write_en,
    input wire [31:0] write_data,
    output wire write_ready,
    output wire write_full,
    output wire write_pixel_credit,
    output wire [8:0] write_level
);

wire app_read_busy;
wire app_write_busy;
wire read_fifo_reset;
wire write_fifo_reset;
wire write_fifo_reset_combined;
wire write_fifo_valid;
wire write_fifo_empty;
wire write_fifo_almost_full;
wire write_fifo_almost_empty;
wire [8:0] write_fifo_write_level;
wire [8:0] write_fifo_read_level;
// Break the FIFO pointer-difference -> writer admission -> reader-state cone.
// In CHECK_FIFO the writer consumes no words, so this is conservative credit.
// Burst/end states let the final pop settle before the next admission check.
reg [8:0] write_fifo_read_level_q;
always @(posedge mem_clk or posedge rst) begin
    if(rst || write_fifo_reset)
        write_fifo_read_level_q <= 9'd0;
    else
        write_fifo_read_level_q <= write_fifo_read_level;
end
assign write_level=write_fifo_write_level;
wire [9:0] read_fifo_mem_level;
wire read_fifo_full;
localparam [9:0] READ_FIFO_BLOCKED_LEVEL = FIFO_DEPTH - 1;
wire [9:0] read_fifo_admission_level;
wire read_budget_permit;
wire write_budget_permit;

generate
    if (READ_BURST_REFRESH_BUDGET != 0) begin : g_read_budget
        read_burst_refresh_budget #(.BURST_WORDS(BURST_SIZE)) u_budget (
            .mem_clk(mem_clk), .rst(rst), .initialized(Sdr_init_done),
            .refresh_active(Sdr_init_ref_vld), .controller_busy(Sdr_busy),
            .permit(read_budget_permit)
        );
    end else begin : g_no_read_budget
        assign read_budget_permit = 1'b1;
    end
endgenerate

// Write protection is opt-in. Only the official writer admission sees this
// term; never mask App_wr_en or FIFO reads during an admitted burst.
generate
    if (WRITE_BURST_REFRESH_BUDGET != 0) begin : g_write_budget
        read_burst_refresh_budget #(.BURST_WORDS(BURST_SIZE)) u_budget (
            .mem_clk(mem_clk), .rst(rst), .initialized(Sdr_init_done),
            .refresh_active(Sdr_init_ref_vld), .controller_busy(Sdr_busy),
            .permit(write_budget_permit)
        );
    end else begin : g_no_write_budget
        assign write_budget_permit = 1'b1;
    end
endgenerate

// Only S_CHECK_FIFO uses this conservative credit. Once admitted, the official
// reader sends its entire burst unchanged, even if busy/refresh rises mid-burst.
// Both guards default off so earlier isolated tops retain their behavior.
assign read_fifo_admission_level =
    (!read_budget_permit || (READ_BURST_IDLE_GUARD && (Sdr_busy || Sdr_init_ref_vld))) ?
    READ_FIFO_BLOCKED_LEVEL : read_fifo_mem_level;

assign App_wr_dm = 4'b0000;
assign write_fifo_reset_combined = rst | write_fifo_reset;
// Board evidence (M5-B board iteration 0, 2026-09-16): back-to-back write
// bursts at ~100% duty make the hardened SDRAM macro commit only one word
// per 128, while the M4-proven slow TF source (sparse bursts) and the read
// path (also near-full duty) are loss-free. The official frame_fifo_write
// has no mid-burst flow control, so the write FIFO input is paced here to
// restore sparse, refill-limited bursts. write_ready stays a per-cycle
// source-domain handshake: the packer holds its word on non-tick cycles, so
// no data is dropped and the loader/packer protocol is unchanged. No
// mem-domain term is allowed here: gating with the mem-domain rst would
// create a mem->source cross-domain setup path into the source-domain
// backpressure chain (M5-B STA iteration 0 evidence, slack +0.106 ns).
reg [7:0] write_pace_cnt;

always @(posedge write_clk or posedge rst) begin
    if (rst)
        write_pace_cnt <= 8'd0;
    else if (write_pace_cnt >= WRITE_PACE_DIV - 1)
        write_pace_cnt <= 8'd0;
    else
        write_pace_cnt <= write_pace_cnt + 8'd1;
end

assign write_ready = ~write_full & (write_pace_cnt == 8'd0);
// Source-domain early credit for a one-cycle pixel pipeline with PACE_DIV=1.
// The generated FIFO asserts almost-full at 509, before full at 511, leaving
// room for in-flight pixels. This pauses the pixel source, not emitted words.
// Paced word producers must continue to use write_ready instead.
assign write_pixel_credit = ~write_fifo_almost_full & ~write_full;

wfifo_32_32_512 u_write_fifo (
    .rst(write_fifo_reset_combined),
    .clkw(write_clk),
    .clkr(mem_clk),
    .we(write_en & write_ready),
    .di(write_data),
    .re(App_wr_en),
    .dout(App_wr_din),
    .valid(write_fifo_valid),
    .full_flag(write_full),
    .empty_flag(write_fifo_empty),
    .afull(write_fifo_almost_full),
    .aempty(write_fifo_almost_empty),
    .wrusedw(write_fifo_write_level),
    .rdusedw(write_fifo_read_level)
);

frame_fifo_write #(
    .MEM_DATA_BITS(MEM_DATA_BITS),
    .ADDR_BITS(ADDR_BITS),
    .BURST_BITS(BURST_BITS),
    .BURST_SIZE(BURST_SIZE),
    .WRITE_V_FLIP(WRITE_V_FLIP),
    .FRAME_WIDTH(FRAME_WIDTH),
    .FRAME_HEIGHT(FRAME_HEIGHT)
) u_frame_fifo_write (
    .rst(rst),
    .mem_clk(mem_clk),
    .Sdr_init_done(Sdr_init_done),
    .Sdr_init_ref_vld(Sdr_init_ref_vld),
    .Sdr_busy(Sdr_busy),
    .App_rd_busy(app_read_busy || !write_budget_permit),
    .O_wr_busy(app_write_busy),
    .App_wr_en(App_wr_en),
    .App_wr_addr(App_wr_addr),
    .write_req(write_req),
    .write_req_ack(write_req_ack),
    .write_finish(write_finish),
    .write_addr_0(write_addr_0),
    .write_addr_1(write_addr_1),
    .write_addr_2(write_addr_2),
    .write_addr_3(write_addr_3),
    .write_addr_index(write_addr_index),
    .write_len(write_len),
    .fifo_aclr(write_fifo_reset),
    .rdusedw({1'b0, write_fifo_read_level_q})
);

frame_read_fifo_rgb565 u_read_fifo (
    .mem_clk(mem_clk),
    .video_clk(read_clk),
    .rst(rst),
    .fifo_reset(read_fifo_reset),
    .mem_write_en(Sdr_rd_en),
    .mem_write_data(Sdr_rd_dout),
    .word_pop(read_pop),
    .clear_faults(clear_read_faults),
    .word_data(read_data),
    .word_valid(read_valid),
    .empty(read_empty),
    .full(read_fifo_full),
    .mem_used_words(read_fifo_mem_level),
    .video_used_words(read_level),
    .underflow_sticky(read_underflow_sticky)
);

frame_fifo_read #(
    .MEM_DATA_BITS(MEM_DATA_BITS),
    .ADDR_BITS(ADDR_BITS),
    .BURST_BITS(BURST_BITS),
    .FIFO_DEPTH(FIFO_DEPTH),
    .BURST_SIZE(BURST_SIZE)
) u_frame_fifo_read (
    .rst(rst),
    .mem_clk(mem_clk),
    .Sdr_init_done(Sdr_init_done),
    .Sdr_init_ref_vld(Sdr_init_ref_vld),
    .Sdr_busy(Sdr_busy),
    .Sdr_rd_en(Sdr_rd_en),
    .App_wr_busy(app_write_busy),
    .O_rd_busy(app_read_busy),
    .App_rd_en(App_rd_en),
    .App_rd_addr(App_rd_addr),
    .read_req(read_req),
    .read_req_ack(read_req_ack),
    .read_finish(read_finish),
    .read_addr_0(read_addr_0),
    .read_addr_1(read_addr_1),
    .read_addr_2(read_addr_2),
    .read_addr_3(read_addr_3),
    .read_addr_index(read_addr_index),
    .read_len(read_len),
    .fifo_aclr(read_fifo_reset),
    .wrusedw(read_fifo_admission_level)
);

endmodule
