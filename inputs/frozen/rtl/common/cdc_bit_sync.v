module cdc_bit_sync (
    input wire clk_dst,
    input wire rst_dst,
    input wire async_in,
    output wire sync_out
);

(* ASYNC_REG = "TRUE" *) reg sync_stage1;
(* ASYNC_REG = "TRUE" *) reg sync_stage2;

assign sync_out = sync_stage2;

always @(posedge clk_dst or posedge rst_dst) begin
    if (rst_dst) begin
        sync_stage1 <= 1'b0;
        sync_stage2 <= 1'b0;
    end else begin
        sync_stage1 <= async_in;
        sync_stage2 <= sync_stage1;
    end
end

endmodule
