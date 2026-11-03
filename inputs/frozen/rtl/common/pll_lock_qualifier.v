`timescale 1ns/1ps
// =============================================================================
// pll_lock_qualifier.v - Require PLL locks to remain stable before reset release
// =============================================================================
// Matches the proven M6-A startup policy: lock loss asserts clocks_ready low
// asynchronously; release occurs only after both synchronized lock inputs remain
// high for LOCK_STABLE_CYCLES reference-clock cycles (1,000,000 @ 50 MHz = 20 ms).
// =============================================================================

module pll_lock_qualifier #(
    parameter integer LOCK_STABLE_CYCLES = 1000000
) (
    input  wire clk_50m,
    input  wire ext_rst_n,
    input  wire sys_pll_lock,
    input  wire hdmi_pll_lock,
    output reg  clocks_ready
);

    wire lock_fault_async = ~ext_rst_n | ~sys_pll_lock | ~hdmi_pll_lock;

    (* ASYNC_REG = "TRUE" *) reg sys_lock_sync1;
    (* ASYNC_REG = "TRUE" *) reg sys_lock_sync2;
    (* ASYNC_REG = "TRUE" *) reg hdmi_lock_sync1;
    (* ASYNC_REG = "TRUE" *) reg hdmi_lock_sync2;
    reg [31:0] stable_count;

    wire all_locks_sync = sys_lock_sync2 & hdmi_lock_sync2;

    always @(posedge clk_50m or posedge lock_fault_async) begin
        if (lock_fault_async) begin
            sys_lock_sync1  <= 1'b0;
            sys_lock_sync2  <= 1'b0;
            hdmi_lock_sync1 <= 1'b0;
            hdmi_lock_sync2 <= 1'b0;
        end else begin
            sys_lock_sync1  <= sys_pll_lock;
            sys_lock_sync2  <= sys_lock_sync1;
            hdmi_lock_sync1 <= hdmi_pll_lock;
            hdmi_lock_sync2 <= hdmi_lock_sync1;
        end
    end

    always @(posedge clk_50m or posedge lock_fault_async) begin
        if (lock_fault_async) begin
            stable_count <= 32'd0;
            clocks_ready <= 1'b0;
        end else if (!all_locks_sync) begin
            stable_count <= 32'd0;
            clocks_ready <= 1'b0;
        end else if (!clocks_ready) begin
            if ((LOCK_STABLE_CYCLES <= 1) ||
                (stable_count >= LOCK_STABLE_CYCLES - 1)) begin
                clocks_ready <= 1'b1;
            end else begin
                stable_count <= stable_count + 32'd1;
            end
        end
    end

endmodule
