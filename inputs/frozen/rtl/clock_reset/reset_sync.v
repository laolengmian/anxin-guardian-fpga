module reset_sync (
    input wire clk,
    input wire async_reset,
    output wire reset_out
);

(* ASYNC_REG = "TRUE" *) reg reset_stage1;
(* ASYNC_REG = "TRUE" *) reg reset_stage2;

assign reset_out = reset_stage2;

always @(posedge clk or posedge async_reset) begin
    if (async_reset) begin
        reset_stage1 <= 1'b1;
        reset_stage2 <= 1'b1;
    end else begin
        reset_stage1 <= 1'b0;
        reset_stage2 <= reset_stage1;
    end
end

endmodule
