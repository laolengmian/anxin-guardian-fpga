`timescale 1ns/1ps

// Fragmentation-aware FAT32 file streamer with downstream backpressure. Adapted
// from the 米处 fat32_file_streamer; cluster-to-LBA arithmetic is shift-only.
module m9_fat32_file_streamer #(
    parameter integer MAX_VISITED_CLUSTERS = 8192
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        file_start,
    input  wire [31:0] first_cluster,
    input  wire [31:0] file_size,
    input  wire [7:0]  sectors_per_cluster,
    input  wire [31:0] fat_start_lba,
    input  wire [31:0] data_start_lba,
    input  wire [31:0] max_cluster,
    output wire        file_busy,
    output reg         file_done,
    output reg         file_valid,
    output reg  [7:0]  file_byte,
    output reg  [31:0] file_byte_offset,
    input  wire        file_ready,
    output reg  [7:0]  fs_error,
    output reg         sector_req,
    output reg  [31:0] sector_lba,
    input  wire        sector_busy,
    input  wire        sector_valid,
    input  wire [7:0]  sector_byte,
    input  wire [8:0]  sector_byte_index,
    input  wire        sector_done,
    input  wire [7:0]  sector_error,
    output wire        sector_ready
);
    localparam [7:0] ERR_NONE              = 8'h00;
    localparam [7:0] ERR_SECTOR            = 8'h10;
    localparam [7:0] ERR_FAT_LOOP          = 8'h23;
    localparam [7:0] ERR_CLUSTER_RANGE     = 8'h24;
    localparam [7:0] ERR_EARLY_EOF         = 8'h25;
    localparam [7:0] ERR_VISITED_EXHAUSTED = 8'h26;
    localparam [7:0] ERR_BAD_SPC           = 8'h27;

    localparam [3:0] ST_IDLE      = 4'd0;
    localparam [3:0] ST_DATA_REQ  = 4'd1;
    localparam [3:0] ST_DATA_WAIT = 4'd2;
    localparam [3:0] ST_FAT_REQ   = 4'd3;
    localparam [3:0] ST_FAT_WAIT  = 4'd4;
    localparam [3:0] ST_FAT_PARSE = 4'd5;
    localparam [3:0] ST_FINISH    = 4'd6;
    // Cluster-to-LBA arithmetic is pipelined one operation per state so the
    // 100 MHz sys_clk cone stays short: ST_PREP registers the per-volume base,
    // ST_LBA_SHIFT the barrel shift, ST_LBA_ADD the final single add.
    localparam [3:0] ST_PREP      = 4'd7;
    localparam [3:0] ST_LBA_SHIFT = 4'd8;
    localparam [3:0] ST_LBA_ADD   = 4'd9;

    localparam integer CHAIN_COUNT_WIDTH =
        (MAX_VISITED_CLUSTERS <= 1) ? 1 : $clog2(MAX_VISITED_CLUSTERS + 1);

    reg [3:0] state;
    reg [31:0] current_cluster;
    reg [31:0] remaining_bytes;
    reg [7:0] sector_in_cluster;
    reg [2:0] sectors_per_cluster_shift;
    reg [8:0] fat_entry_offset;
    reg [7:0] fat_byte0;
    reg [7:0] fat_byte1;
    reg [7:0] fat_byte2;
    reg [7:0] fat_byte3;
    reg [CHAIN_COUNT_WIDTH-1:0] chain_count;
    reg final_chain_check;
    reg fat_eoc_q;
    reg fat_range_q;
    reg fat_loop_q;
    reg [31:0] lba_base;
    reg [31:0] cluster_shifted;

    wire [27:0] next_cluster =
        {fat_byte3[3:0], fat_byte2, fat_byte1, fat_byte0};
    // sector_done may coincide with the final selected FAT byte. Feed that
    // accepted byte forward into the registered validation decision instead
    // of classifying the pre-edge byte registers.
    wire [7:0] fat_byte0_effective =
        sector_valid && sector_byte_index == fat_entry_offset ?
        sector_byte : fat_byte0;
    wire [7:0] fat_byte1_effective =
        sector_valid && sector_byte_index == fat_entry_offset + 1'b1 ?
        sector_byte : fat_byte1;
    wire [7:0] fat_byte2_effective =
        sector_valid && sector_byte_index == fat_entry_offset + 2'd2 ?
        sector_byte : fat_byte2;
    wire [7:0] fat_byte3_effective =
        sector_valid && sector_byte_index == fat_entry_offset + 2'd3 ?
        sector_byte : fat_byte3;
    wire [27:0] next_cluster_effective = {
        fat_byte3_effective[3:0], fat_byte2_effective,
        fat_byte1_effective, fat_byte0_effective
    };

    assign file_busy = state != ST_IDLE;
    assign sector_ready =
        (state == ST_DATA_WAIT && remaining_bytes != 0) ?
        (!file_valid || file_ready) : 1'b1;

    function valid_spc;
        input [7:0] value;
        begin
            valid_spc = value != 0 && ((value & (value - 1'b1)) == 0);
        end
    endfunction

    function [2:0] spc_shift;
        input [7:0] value;
        begin
            case (value)
                8'd1:   spc_shift = 3'd0;
                8'd2:   spc_shift = 3'd1;
                8'd4:   spc_shift = 3'd2;
                8'd8:   spc_shift = 3'd3;
                8'd16:  spc_shift = 3'd4;
                8'd32:  spc_shift = 3'd5;
                8'd64:  spc_shift = 3'd6;
                8'd128: spc_shift = 3'd7;
                default: spc_shift = 3'd0;
            endcase
        end
    endfunction

    // sector_lba = data_start_lba + ((cluster - 2) << shift) is evaluated as
    // cluster_shifted + lba_base with lba_base = data_start_lba - (2 << shift).
    // Both forms are bit-identical mod 2^32 (truncating shift distributes over
    // subtraction), and splitting them keeps each pipeline stage a single
    // barrel shift or a single 32-bit add.

    // Parallel half-word comparisons avoid a 32-bit serial carry chain.
    // Strict unsigned ordering is unchanged, including equal high halves.
    function less_u32;
        input [31:0] left_value,right_value;
        begin
            less_u32=(left_value[31:16] < right_value[31:16]) ||
                ((left_value[31:16] == right_value[31:16]) &&
                 (left_value[15:0] < right_value[15:0]));
        end
    endfunction

    task finish_with_error;
        input [7:0] code;
        begin
            fs_error <= code;
            state <= ST_FINISH;
        end
    endtask

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ST_IDLE;
            current_cluster <= 32'd0;
            remaining_bytes <= 32'd0;
            sector_in_cluster <= 8'd0;
            sectors_per_cluster_shift <= 3'd0;
            fat_entry_offset <= 9'd0;
            fat_byte0 <= 8'd0;
            fat_byte1 <= 8'd0;
            fat_byte2 <= 8'd0;
            fat_byte3 <= 8'd0;
            chain_count <= 0;
            final_chain_check <= 1'b0;
            fat_eoc_q <= 1'b0;
            fat_range_q <= 1'b0;
            fat_loop_q <= 1'b0;
            lba_base <= 32'd0;
            cluster_shifted <= 32'd0;
            file_done <= 1'b0;
            file_valid <= 1'b0;
            file_byte <= 8'd0;
            file_byte_offset <= 32'd0;
            fs_error <= ERR_NONE;
            sector_req <= 1'b0;
            sector_lba <= 32'd0;
        end else begin
            file_done <= 1'b0;
            sector_req <= 1'b0;

            if (file_valid && file_ready)
                file_valid <= 1'b0;

            if (state == ST_DATA_WAIT && sector_valid && sector_ready &&
                remaining_bytes != 0) begin
                file_valid <= 1'b1;
                file_byte <= sector_byte;
                file_byte_offset <= file_size - remaining_bytes;
                remaining_bytes <= remaining_bytes - 1'b1;
            end

            if (state == ST_FAT_WAIT && sector_valid) begin
                if (sector_byte_index == fat_entry_offset)
                    fat_byte0 <= sector_byte;
                else if (sector_byte_index == fat_entry_offset + 1'b1)
                    fat_byte1 <= sector_byte;
                else if (sector_byte_index == fat_entry_offset + 2'd2)
                    fat_byte2 <= sector_byte;
                else if (sector_byte_index == fat_entry_offset + 2'd3)
                    fat_byte3 <= sector_byte;
            end

            case (state)
                ST_IDLE: begin
                    if (file_start) begin
                        fs_error <= ERR_NONE;
                        file_valid <= 1'b0;
                        file_byte_offset <= 32'd0;
                        remaining_bytes <= file_size;
                        sector_in_cluster <= 8'd0;
                        chain_count <= 1;
                        final_chain_check <= 1'b0;
                        fat_eoc_q <= 1'b0;
                        fat_range_q <= 1'b0;
                        fat_loop_q <= 1'b0;
                        if (!valid_spc(sectors_per_cluster)) begin
                            finish_with_error(ERR_BAD_SPC);
                        end else if (file_size == 0) begin
                            state <= ST_FINISH;
                        end else if (first_cluster < 2 ||
                                     less_u32(max_cluster,first_cluster)) begin
                            finish_with_error(ERR_CLUSTER_RANGE);
                        end else begin
                            sectors_per_cluster_shift <=
                                spc_shift(sectors_per_cluster);
                            current_cluster <= first_cluster;
                            state <= ST_PREP;
                        end
                    end
                end

                ST_PREP: begin
                    lba_base <= data_start_lba -
                                (32'd2 << sectors_per_cluster_shift);
                    state <= ST_LBA_SHIFT;
                end

                ST_LBA_SHIFT: begin
                    cluster_shifted <= current_cluster <<
                                       sectors_per_cluster_shift;
                    state <= ST_LBA_ADD;
                end

                ST_LBA_ADD: begin
                    sector_lba <= cluster_shifted + lba_base;
                    state <= ST_DATA_REQ;
                end

                ST_DATA_REQ: begin
                    if (!sector_busy) begin
                        sector_req <= 1'b1;
                        state <= ST_DATA_WAIT;
                    end
                end

                ST_DATA_WAIT: begin
                    if (sector_done) begin
                        if (sector_error != 0) begin
                            finish_with_error(ERR_SECTOR);
                        end else if (remaining_bytes == 0) begin
                            final_chain_check <= 1'b1;
                            sector_in_cluster <= 8'd0;
                            fat_entry_offset <= {current_cluster[6:0], 2'b00};
                            sector_lba <= fat_start_lba + (current_cluster >> 7);
                            state <= ST_FAT_REQ;
                        end else if (sector_in_cluster + 1'b1 <
                                     sectors_per_cluster) begin
                            sector_in_cluster <= sector_in_cluster + 1'b1;
                            sector_lba <= sector_lba + 1'b1;
                            state <= ST_DATA_REQ;
                        end else begin
                            sector_in_cluster <= 8'd0;
                            fat_entry_offset <= {current_cluster[6:0], 2'b00};
                            sector_lba <= fat_start_lba + (current_cluster >> 7);
                            state <= ST_FAT_REQ;
                        end
                    end
                end

                ST_FAT_REQ: begin
                    if (!sector_busy) begin
                        sector_req <= 1'b1;
                        state <= ST_FAT_WAIT;
                    end
                end

                ST_FAT_WAIT: begin
                    if (sector_done) begin
                        if (sector_error != 0) begin
                            finish_with_error(ERR_SECTOR);
                        end else begin
                            fat_eoc_q <=
                                next_cluster_effective >= 28'hffffff8;
                            fat_range_q <=
                                next_cluster_effective < 2 ||
                                next_cluster_effective > max_cluster;
                            fat_loop_q <=
                                next_cluster_effective == current_cluster;
                            state <= ST_FAT_PARSE;
                        end
                    end
                end

                ST_FAT_PARSE: begin
                    // Stage the working set independently of wide validation.
                    // Only the validated state transition can issue a sector;
                    // errors finish, and file_start reinitializes this set.
                    current_cluster <= {4'd0, next_cluster};
                    chain_count <= chain_count + 1'b1;
                    sector_in_cluster <= 8'd0;
                    if (final_chain_check) begin
                        final_chain_check <= 1'b0;
                        if (fat_eoc_q)
                            state <= ST_FINISH;
                        else if (fat_range_q)
                            finish_with_error(ERR_CLUSTER_RANGE);
                        else
                            finish_with_error(ERR_FAT_LOOP);
                    end else if (fat_eoc_q) begin
                        finish_with_error(ERR_EARLY_EOF);
                    end else if (fat_range_q) begin
                        finish_with_error(ERR_CLUSTER_RANGE);
                    end else if (chain_count >= MAX_VISITED_CLUSTERS) begin
                        finish_with_error(ERR_VISITED_EXHAUSTED);
                    end else if (fat_loop_q) begin
                        finish_with_error(ERR_FAT_LOOP);
                    end else begin
                        state <= ST_LBA_SHIFT;
                    end
                end

                ST_FINISH: begin
                    file_done <= 1'b1;
                    state <= ST_IDLE;
                end

                default: state <= ST_IDLE;
            endcase
        end
    end
endmodule
