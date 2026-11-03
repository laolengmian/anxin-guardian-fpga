module cdc_event_toggle (
    input wire src_clk,
    input wire src_rst,
    input wire src_event,
    input wire dst_clk,
    input wire dst_rst,
    output reg dst_pulse
);

reg src_toggle;
(* ASYNC_REG = "TRUE" *) reg dst_sync_stage1;
(* ASYNC_REG = "TRUE" *) reg dst_sync_stage2;
reg dst_seen_toggle;

always @(posedge src_clk or posedge src_rst) begin
    if (src_rst)
        src_toggle <= 1'b0;
    else if (src_event)
        src_toggle <= ~src_toggle;
end

always @(posedge dst_clk or posedge dst_rst) begin
    if (dst_rst) begin
        dst_sync_stage1 <= 1'b0;
        dst_sync_stage2 <= 1'b0;
        dst_seen_toggle <= 1'b0;
        dst_pulse <= 1'b0;
    end else begin
        dst_sync_stage1 <= src_toggle;
        dst_sync_stage2 <= dst_sync_stage1;
        dst_seen_toggle <= dst_sync_stage2;
        dst_pulse <= dst_sync_stage2 ^ dst_seen_toggle;
    end
end

endmodule
