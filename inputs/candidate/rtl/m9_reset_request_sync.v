`timescale 1ns/1ps

// Synchronize the debounced KEY5 level into one destination reset domain.
// The original onboard A2 reset clears this synchronizer; KEY5 must never
// clear its own request while the reset it requested is active.
module m9_reset_request_sync (
    input  wire clk,
    input  wire clear,
    input  wire request_async,
    output wire request_sync
);

    (* ASYNC_REG = "TRUE" *) reg sync_stage1;
    (* ASYNC_REG = "TRUE" *) reg sync_stage2;

    assign request_sync = sync_stage2;

    always @(posedge clk or posedge clear) begin
        if (clear) begin
            sync_stage1 <= 1'b0;
            sync_stage2 <= 1'b0;
        end else begin
            sync_stage1 <= request_async;
            sync_stage2 <= sync_stage1;
        end
    end

endmodule
