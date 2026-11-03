`timescale 1ns/1ps

// M9-private CMD17 reader. A registered completion boundary keeps sampled
// SPI data out of the protocol/error decision cone without changing bytes.
module m9_sd_spi_sector_reader #(
    parameter integer SPI_CLK_DIV = 2,
    parameter integer MAX_R1_BYTES = 16,
    parameter integer MAX_TOKEN_BYTES = 65536,
    parameter CHECK_DATA_CRC = 1'b1
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        init_ready,
    input  wire        card_high_capacity,
    input  wire        sector_req,
    input  wire [31:0] sector_lba,
    output wire        sector_busy,
    output reg         sector_done,
    output reg         sector_valid,
    output reg  [7:0]  sector_byte,
    output reg  [8:0]  sector_byte_index,
    output reg  [7:0]  sector_error,
    output reg  [7:0]  last_r1,
    output wire        sd_cs_n,
    output wire        sd_sclk,
    output wire        sd_mosi,
    input  wire        sd_miso
);
    localparam [7:0] ERR_NONE          = 8'h00;
    localparam [7:0] ERR_R1_TIMEOUT    = 8'h01;
    localparam [7:0] ERR_R1_STATUS     = 8'h02;
    localparam [7:0] ERR_TOKEN_TIMEOUT = 8'h03;
    localparam [7:0] ERR_BAD_TOKEN     = 8'h04;
    localparam [7:0] ERR_DATA_CRC      = 8'h05;
    localparam [7:0] ERR_NOT_READY     = 8'h06;
    localparam [7:0] ERR_LBA_RANGE     = 8'h07;

    localparam [4:0] ST_IDLE       = 5'd0;
    localparam [4:0] ST_PRE_REQ    = 5'd1;
    localparam [4:0] ST_PRE_WAIT   = 5'd2;
    localparam [4:0] ST_CMD_REQ    = 5'd3;
    localparam [4:0] ST_CMD_WAIT   = 5'd4;
    localparam [4:0] ST_R1_REQ     = 5'd5;
    localparam [4:0] ST_R1_WAIT    = 5'd6;
    localparam [4:0] ST_TOKEN_REQ  = 5'd7;
    localparam [4:0] ST_TOKEN_WAIT = 5'd8;
    localparam [4:0] ST_DATA_REQ   = 5'd9;
    localparam [4:0] ST_DATA_WAIT  = 5'd10;
    localparam [4:0] ST_CRC_H_REQ  = 5'd11;
    localparam [4:0] ST_CRC_H_WAIT = 5'd12;
    localparam [4:0] ST_CRC_L_REQ  = 5'd13;
    localparam [4:0] ST_CRC_L_WAIT = 5'd14;
    localparam [4:0] ST_POST_REQ   = 5'd15;
    localparam [4:0] ST_POST_WAIT  = 5'd16;

    reg [4:0] state;
    reg [2:0] cmd_byte_index;
    reg [31:0] command_argument;
    reg [8:0] data_count;
    reg [15:0] data_crc;
    reg [7:0] received_crc_high;
    integer r1_poll_count;
    integer token_poll_count;

    reg byte_start;
    reg [7:0] byte_tx;
    wire byte_busy;
    wire byte_done;
    wire [7:0] byte_rx;
    reg byte_done_q /* fehdl keep="true" */;
    reg [7:0] byte_rx_q /* fehdl keep="true" */;

    assign sector_busy = state != ST_IDLE;
    assign sd_cs_n = state == ST_IDLE || state == ST_PRE_REQ ||
                     state == ST_PRE_WAIT || state == ST_POST_REQ ||
                     state == ST_POST_WAIT;

    function [7:0] command_byte;
        input [2:0] index;
        begin
            case (index)
                3'd0: command_byte = 8'h51;
                3'd1: command_byte = command_argument[31:24];
                3'd2: command_byte = command_argument[23:16];
                3'd3: command_byte = command_argument[15:8];
                3'd4: command_byte = command_argument[7:0];
                default: command_byte = 8'hff;
            endcase
        end
    endfunction

    function [15:0] crc16_byte;
        input [15:0] crc_in;
        input [7:0] data_in;
        integer i;
        reg [15:0] crc_work;
        begin
            crc_work = crc_in;
            for (i = 0; i < 8; i = i + 1) begin
                if (crc_work[15] ^ data_in[7-i])
                    crc_work = {crc_work[14:0], 1'b0} ^ 16'h1021;
                else
                    crc_work = {crc_work[14:0], 1'b0};
            end
            crc16_byte = crc_work;
        end
    endfunction

    sd_spi_byte_engine_m6c #(.CLK_DIV(SPI_CLK_DIV)) u_byte_engine (
        .clk(clk), .rst_n(rst_n), .start(byte_start), .tx_byte(byte_tx),
        .miso(sd_miso), .busy(byte_busy), .done(byte_done),
        .rx_byte(byte_rx), .sclk(sd_sclk), .mosi(sd_mosi)
    );

    task finish_with_error;
        input [7:0] code;
        begin
            sector_error <= code;
            state <= ST_POST_REQ;
        end
    endtask

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ST_IDLE;
            cmd_byte_index <= 3'd0;
            command_argument <= 32'd0;
            data_count <= 9'd0;
            data_crc <= 16'd0;
            received_crc_high <= 8'd0;
            r1_poll_count <= 0;
            token_poll_count <= 0;
            byte_start <= 1'b0;
            byte_tx <= 8'hff;
            sector_done <= 1'b0;
            sector_valid <= 1'b0;
            sector_byte <= 8'd0;
            sector_byte_index <= 9'd0;
            sector_error <= ERR_NONE;
            last_r1 <= 8'hff;
            byte_done_q <= 1'b0;
            byte_rx_q <= 8'h00;
        end else begin
            byte_done_q <= byte_done;
            if (byte_done)
                byte_rx_q <= byte_rx;
            byte_start <= 1'b0;
            sector_done <= 1'b0;
            sector_valid <= 1'b0;
            case (state)
                ST_IDLE: begin
                    if (sector_req) begin
                        sector_error <= ERR_NONE;
                        last_r1 <= 8'hff;
                        if (!init_ready) begin
                            sector_error <= ERR_NOT_READY;
                            sector_done <= 1'b1;
                        end else if (!card_high_capacity &&
                                     |sector_lba[31:23]) begin
                            sector_error <= ERR_LBA_RANGE;
                            sector_done <= 1'b1;
                        end else begin
                            command_argument <= card_high_capacity ?
                                                sector_lba : (sector_lba << 9);
                            cmd_byte_index <= 3'd0;
                            r1_poll_count <= 0;
                            token_poll_count <= 0;
                            data_count <= 9'd0;
                            data_crc <= 16'd0;
                            state <= ST_PRE_REQ;
                        end
                    end
                end
                ST_PRE_REQ: begin
                    if (!byte_busy) begin
                        byte_tx <= 8'hff;
                        byte_start <= 1'b1;
                        state <= ST_PRE_WAIT;
                    end
                end
                ST_PRE_WAIT: begin
                    if (byte_done_q) begin
                        byte_tx <= command_byte(3'd0);
                        state <= ST_CMD_REQ;
                    end
                end
                ST_CMD_REQ: begin
                    if (!byte_busy) begin
                        byte_start <= 1'b1;
                        state <= ST_CMD_WAIT;
                    end
                end
                ST_CMD_WAIT: begin
                    if (byte_done_q) begin
                        if (cmd_byte_index == 3'd5) begin
                            r1_poll_count <= 0;
                            state <= ST_R1_REQ;
                        end else begin
                            cmd_byte_index <= cmd_byte_index + 1'b1;
                            byte_tx <= command_byte(cmd_byte_index + 1'b1);
                            state <= ST_CMD_REQ;
                        end
                    end
                end
                ST_R1_REQ: begin
                    if (!byte_busy) begin
                        byte_tx <= 8'hff;
                        byte_start <= 1'b1;
                        state <= ST_R1_WAIT;
                    end
                end
                ST_R1_WAIT: begin
                    if (byte_done_q) begin
                        if (!byte_rx_q[7]) begin
                            last_r1 <= byte_rx_q;
                            if (byte_rx_q == 8'h00) begin
                                token_poll_count <= 0;
                                state <= ST_TOKEN_REQ;
                            end else
                                finish_with_error(ERR_R1_STATUS);
                        end else if (r1_poll_count == MAX_R1_BYTES - 1)
                            finish_with_error(ERR_R1_TIMEOUT);
                        else begin
                            r1_poll_count <= r1_poll_count + 1;
                            state <= ST_R1_REQ;
                        end
                    end
                end
                ST_TOKEN_REQ: begin
                    if (!byte_busy) begin
                        byte_tx <= 8'hff;
                        byte_start <= 1'b1;
                        state <= ST_TOKEN_WAIT;
                    end
                end
                ST_TOKEN_WAIT: begin
                    if (byte_done_q) begin
                        if (byte_rx_q == 8'hfe) begin
                            data_count <= 9'd0;
                            data_crc <= 16'd0;
                            state <= ST_DATA_REQ;
                        end else if (byte_rx_q != 8'hff)
                            finish_with_error(ERR_BAD_TOKEN);
                        else if (token_poll_count == MAX_TOKEN_BYTES - 1)
                            finish_with_error(ERR_TOKEN_TIMEOUT);
                        else begin
                            token_poll_count <= token_poll_count + 1;
                            state <= ST_TOKEN_REQ;
                        end
                    end
                end
                ST_DATA_REQ: begin
                    if (!byte_busy) begin
                        byte_tx <= 8'hff;
                        byte_start <= 1'b1;
                        state <= ST_DATA_WAIT;
                    end
                end
                ST_DATA_WAIT: begin
                    if (byte_done_q) begin
                        sector_byte <= byte_rx_q;
                        sector_byte_index <= data_count;
                        sector_valid <= 1'b1;
                        data_crc <= crc16_byte(data_crc, byte_rx_q);
                        if (data_count == 9'd511)
                            state <= ST_CRC_H_REQ;
                        else begin
                            data_count <= data_count + 1'b1;
                            state <= ST_DATA_REQ;
                        end
                    end
                end
                ST_CRC_H_REQ: begin
                    if (!byte_busy) begin
                        byte_tx <= 8'hff;
                        byte_start <= 1'b1;
                        state <= ST_CRC_H_WAIT;
                    end
                end
                ST_CRC_H_WAIT: begin
                    if (byte_done_q) begin
                        received_crc_high <= byte_rx_q;
                        state <= ST_CRC_L_REQ;
                    end
                end
                ST_CRC_L_REQ: begin
                    if (!byte_busy) begin
                        byte_tx <= 8'hff;
                        byte_start <= 1'b1;
                        state <= ST_CRC_L_WAIT;
                    end
                end
                ST_CRC_L_WAIT: begin
                    if (byte_done_q) begin
                        if (CHECK_DATA_CRC &&
                            {received_crc_high, byte_rx_q} != data_crc)
                            sector_error <= ERR_DATA_CRC;
                        state <= ST_POST_REQ;
                    end
                end
                ST_POST_REQ: begin
                    if (!byte_busy) begin
                        byte_tx <= 8'hff;
                        byte_start <= 1'b1;
                        state <= ST_POST_WAIT;
                    end
                end
                ST_POST_WAIT: begin
                    if (byte_done_q) begin
                        sector_done <= 1'b1;
                        state <= ST_IDLE;
                    end
                end
                default: state <= ST_IDLE;
            endcase
        end
    end
endmodule
