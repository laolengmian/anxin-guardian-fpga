module frame_read_fifo_rgb565 (
    input wire mem_clk,
    input wire video_clk,
    input wire rst,
    input wire fifo_reset,
    input wire mem_write_en,
    input wire [31:0] mem_write_data,
    input wire word_pop,
    input wire clear_faults,
    output wire [31:0] word_data,
    output wire word_valid,
    output wire empty,
    output wire full,
    output wire [9:0] mem_used_words,
    output wire [9:0] video_used_words,
    output reg underflow_sticky
);

wire fifo_rst;
wire almost_full;
wire almost_empty;
wire [8:0] write_used_words;
wire [8:0] read_used_words;
wire fifo_read_en;

assign fifo_rst = rst | fifo_reset;
assign fifo_read_en = word_pop & word_valid;
assign mem_used_words = {1'b0, write_used_words};
assign video_used_words = {1'b0, read_used_words};

rfifo_32_32_512 #(
    .SHOW_AHEAD_EN(1'b1),
    .OUTREG_EN("NOREG")
) u_read_fifo (
    .rst(fifo_rst),
    .clkw(mem_clk),
    .clkr(video_clk),
    .we(mem_write_en),
    .di(mem_write_data),
    .re(fifo_read_en),
    .dout(word_data),
    .valid(word_valid),
    .full_flag(full),
    .empty_flag(empty),
    .afull(almost_full),
    .aempty(almost_empty),
    .wrusedw(write_used_words),
    .rdusedw(read_used_words)
);

always @(posedge video_clk or posedge fifo_rst) begin
    if (fifo_rst)
        underflow_sticky <= 1'b0;
    else if (clear_faults)
        underflow_sticky <= 1'b0;
    else if (word_pop && !word_valid)
        underflow_sticky <= 1'b1;
end

endmodule
