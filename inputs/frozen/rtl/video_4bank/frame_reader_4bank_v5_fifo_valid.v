`timescale 1ns/1ps
// =============================================================================
// frame_reader_4bank_v5_fifo_valid.v - RFIFO-valid-driven four-bank reader
// Date: 2026-09-21
//
// v10-v12 attempted to infer SDRAM/RFIFO availability from refresh timing. That
// cannot prove that a read-clock pop was accepted: the generated RFIFO silently
// suppresses re while empty and leaves dout at its previous value. Counting such
// an attempted pop as a new word duplicates stale data and shifts every later
// pixel. V5 consumes the existing show-ahead RFIFO interface used by the verified
// M5/M6-A path. A word advances only on read_pop && read_valid; empty intervals
// simply defer the pop, and the normal horizontal-blanking schedule repays debt.
//
// The official frame_fifo_read/write and SDRAM RTL remain unchanged. The owning
// frame_read_write_rgb565 integration wrapper only exposes the generated RFIFO's
// existing valid/empty/level outputs.
// =============================================================================

module frame_reader_4bank_v5_fifo_valid #(
    parameter integer WORDS_PER_FRAME = 460800
) (
    input  wire        video_clk,
    input  wire        rst_n,

    input  wire [1:0]  bank_select,
    input  wire        frame_boundary,
    input  wire        de,
    input  wire [11:0] pixel_x,

    output reg         read_req,
    input  wire        read_req_ack,
    input  wire        read_finish,
    output wire        read_pop,
    input  wire [31:0] read_data,
    input  wire        read_valid,
    input  wire        read_empty,
    input  wire [9:0]  read_level,
    output wire [20:0] read_addr_0,
    output wire [20:0] read_addr_1,
    output wire [20:0] read_addr_2,
    output wire [20:0] read_addr_3,
    output wire [1:0]  read_addr_index,
    output wire [20:0] read_len,

    input  wire        out_fifo_pause,
    output reg         pixel_valid,
    output reg  [23:0] rgb888_out,

    output reg         underflow_sticky,
    output wire [31:0] dbg_pixels_emitted
);

    localparam R_IDLE         = 3'd0;
    localparam R_TRIG_DLY     = 3'd1;
    localparam R_REQ          = 3'd2;
    localparam R_WAIT_ACK_LOW = 3'd3;
    localparam R_RUN          = 3'd4;

    reg [2:0]  state;
    reg [1:0]  bank_r;
    reg [31:0] req_cnt;
    reg [31:0] px_cnt;
    reg [5:0]  trig_dly_cnt;

    wire sess_start = (state == R_TRIG_DLY) && (trig_dly_cnt == 6'd63);
    wire frame_data_done =
        (px_cnt >= WORDS_PER_FRAME[31:0] * 2 - 32'd64);

    reg ack_sync1;
    reg ack_sync2;
    always @(posedge video_clk or negedge rst_n) begin
        if (!rst_n) begin
            ack_sync1 <= 1'b0;
            ack_sync2 <= 1'b0;
        end else begin
            ack_sync1 <= read_req_ack;
            ack_sync2 <= ack_sync1;
        end
    end

    always @(posedge video_clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= R_IDLE;
            bank_r       <= 2'd0;
            read_req     <= 1'b0;
            trig_dly_cnt <= 6'd0;
        end else begin
            case (state)
                R_IDLE: begin
                    if (frame_boundary) begin
                        trig_dly_cnt <= 6'd0;
                        state        <= R_TRIG_DLY;
                    end
                end

                R_TRIG_DLY: begin
                    trig_dly_cnt <= trig_dly_cnt + 6'd1;
                    if (trig_dly_cnt == 6'd63) begin
                        bank_r   <= bank_select;
                        read_req <= 1'b1;
                        state    <= R_REQ;
                    end
                end

                R_REQ: begin
                    if (ack_sync2) begin
                        read_req <= 1'b0;
                        state    <= R_WAIT_ACK_LOW;
                    end
                end

                R_WAIT_ACK_LOW: begin
                    if (!ack_sync2)
                        state <= R_RUN;
                end

                R_RUN: begin
                    if (frame_boundary && frame_data_done) begin
                        trig_dly_cnt <= 6'd0;
                        state        <= R_TRIG_DLY;
                    end
                end

                default: state <= R_IDLE;
            endcase
        end
    end

    localparam integer PRESTAGE_WORDS = 120;
    localparam integer SCHED_LEAD = 4 + 2 * PRESTAGE_WORDS;

    wire frame_run = (state == R_RUN);
    reg [6:0] run_cnt;
    wire run_ready = frame_run && (run_cnt >= 7'd64);

    always @(posedge video_clk or negedge rst_n) begin
        if (!rst_n)
            run_cnt <= 7'd0;
        else if (!frame_run)
            run_cnt <= 7'd0;
        else if (!run_cnt[6])
            run_cnt <= run_cnt + 7'd1;
    end

    reg [19:0] de_pc;
    always @(posedge video_clk or negedge rst_n) begin
        if (!rst_n)
            de_pc <= 20'd0;
        else if (sess_start)
            de_pc <= 20'd0;
        else if (de)
            de_pc <= de_pc + 20'd1;
    end

    wire [20:0] sched_thresh = {req_cnt[19:0], 1'b0};
    wire [20:0] sched_pc = {1'b0, de_pc} + SCHED_LEAD[20:0];
    wire pre_stage = !de && (req_cnt < PRESTAGE_WORDS[31:0]);
    wire sched_due = sched_pc >= sched_thresh;
    wire request_due = run_ready && !out_fifo_pause &&
                       (req_cnt < WORDS_PER_FRAME[31:0]) &&
                       (pre_stage || sched_due);

    reg        have_word;
    reg        half;
    reg [31:0] word_r;

    wire emit_en = have_word &&
                   (px_cnt < WORDS_PER_FRAME[31:0] * 2) &&
                   !out_fifo_pause;
    wire emit_hi = emit_en && half;
    wire capture_slot = !have_word || emit_hi;
    wire fifo_word_available = read_valid && !read_empty;

    // Show-ahead FIFO contract: read_data is the current head while read_valid is
    // high. The same edge can emit the old word's high pixel and capture the next
    // head, sustaining one 32-bit word per two video clocks without stale reads.
    assign read_pop = request_due && capture_slot && fifo_word_available;

    always @(posedge video_clk or negedge rst_n) begin
        if (!rst_n)
            req_cnt <= 32'd0;
        else if (sess_start)
            req_cnt <= 32'd0;
        else if (read_pop)
            req_cnt <= req_cnt + 32'd1;
    end

    always @(posedge video_clk or negedge rst_n) begin
        if (!rst_n)
            word_r <= 32'd0;
        else if (read_pop)
            word_r <= read_data;
    end

    always @(posedge video_clk or negedge rst_n) begin
        if (!rst_n || sess_start)
            have_word <= 1'b0;
        else begin
            case ({read_pop, emit_hi})
                2'b10, 2'b11: have_word <= 1'b1;
                2'b01:        have_word <= 1'b0;
                default:      have_word <= have_word;
            endcase
        end
    end

    always @(posedge video_clk or negedge rst_n) begin
        if (!rst_n || sess_start)
            underflow_sticky <= 1'b0;
        else if (request_due && !fifo_word_available && !have_word)
            underflow_sticky <= 1'b1;
    end

    always @(posedge video_clk or negedge rst_n) begin
        if (!rst_n) begin
            pixel_valid <= 1'b0;
            rgb888_out  <= 24'd0;
            half        <= 1'b0;
            px_cnt      <= 32'd0;
        end else begin
            pixel_valid <= 1'b0;

            if (sess_start) begin
                half   <= 1'b0;
                px_cnt <= 32'd0;
            end else if (emit_en) begin
                pixel_valid <= 1'b1;
                rgb888_out <= half ? {word_r[31:27], 3'b000,
                                      word_r[26:21], 2'b00,
                                      word_r[20:16], 3'b000}
                                   : {word_r[15:11], 3'b000,
                                      word_r[10:5], 2'b00,
                                      word_r[4:0], 3'b000};
                half   <= ~half;
                px_cnt <= px_cnt + 32'd1;
            end
        end
    end

    assign dbg_pixels_emitted = px_cnt;
    assign read_addr_0 = 21'h000000;
    assign read_addr_1 = 21'h070800;
    assign read_addr_2 = 21'h0E1000;
    assign read_addr_3 = 21'h151800;
    assign read_addr_index = bank_r;
    assign read_len = WORDS_PER_FRAME[20:0];

endmodule
