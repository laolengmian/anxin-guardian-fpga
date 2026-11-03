module cdc_frame_commit (
    input wire src_clk,
    input wire src_rst,
    input wire src_request,
    input wire [1:0] src_buf_idx,
    output reg src_busy,
    output reg src_ack_pulse,
    output reg src_reject_pulse,
    input wire dst_clk,
    input wire dst_rst,
    input wire frame_boundary,
    output reg dst_commit_pulse,
    output reg [1:0] dst_buf_idx
);

reg src_request_toggle;
(* KEEP = "TRUE" *) reg [1:0] src_held_buf_idx;
(* ASYNC_REG = "TRUE" *) reg src_ack_sync_stage1;
(* ASYNC_REG = "TRUE" *) reg src_ack_sync_stage2;

(* ASYNC_REG = "TRUE" *) reg dst_request_sync_stage1;
(* ASYNC_REG = "TRUE" *) reg dst_request_sync_stage2;
reg dst_ack_toggle;

wire dst_request_pending;

assign dst_request_pending =
    dst_request_sync_stage2 != dst_ack_toggle;

always @(posedge src_clk or posedge src_rst) begin
    if (src_rst) begin
        src_request_toggle <= 1'b0;
        src_held_buf_idx <= 2'd0;
        src_ack_sync_stage1 <= 1'b0;
        src_ack_sync_stage2 <= 1'b0;
        src_busy <= 1'b0;
        src_ack_pulse <= 1'b0;
        src_reject_pulse <= 1'b0;
    end else begin
        src_ack_sync_stage1 <= dst_ack_toggle;
        src_ack_sync_stage2 <= src_ack_sync_stage1;
        src_ack_pulse <= 1'b0;
        src_reject_pulse <= 1'b0;

        if (src_busy) begin
            if (src_ack_sync_stage2 == src_request_toggle) begin
                src_busy <= 1'b0;
                src_ack_pulse <= 1'b1;
            end
            if (src_request)
                src_reject_pulse <= 1'b1;
        end else if (src_request) begin
            src_held_buf_idx <= src_buf_idx;
            src_request_toggle <= ~src_request_toggle;
            src_busy <= 1'b1;
        end
    end
end

always @(posedge dst_clk or posedge dst_rst) begin
    if (dst_rst) begin
        dst_request_sync_stage1 <= 1'b0;
        dst_request_sync_stage2 <= 1'b0;
        dst_ack_toggle <= 1'b0;
        dst_commit_pulse <= 1'b0;
        dst_buf_idx <= 2'd0;
    end else begin
        dst_request_sync_stage1 <= src_request_toggle;
        dst_request_sync_stage2 <= dst_request_sync_stage1;
        dst_commit_pulse <= 1'b0;

        if (dst_request_pending && frame_boundary) begin
            dst_buf_idx <= src_held_buf_idx;
            dst_commit_pulse <= 1'b1;
            dst_ack_toggle <= dst_request_sync_stage2;
        end
    end
end

endmodule
