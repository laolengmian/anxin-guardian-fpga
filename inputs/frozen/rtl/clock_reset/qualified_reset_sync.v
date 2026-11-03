module qualified_reset_sync (
    input wire clk,
    input wire async_assert,
    input wire release_async,
    output wire reset_out
);

(* ASYNC_REG = "TRUE" *) reg release_stage1;
(* ASYNC_REG = "TRUE" *) reg release_stage2;

assign reset_out = ~release_stage2;

always @(posedge clk or posedge async_assert) begin
    if (async_assert) begin
        release_stage1 <= 1'b0;
        release_stage2 <= 1'b0;
    end else begin
        release_stage1 <= release_async;
        release_stage2 <= release_stage1;
    end
end

endmodule
