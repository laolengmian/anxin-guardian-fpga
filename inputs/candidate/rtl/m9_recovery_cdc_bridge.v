// Explicit M9-C event crossings between the always-observable 50 MHz Health
// domain and the 100 MHz media domain. Reset fences discard toggle parity
// replays, and result events are accepted only for an armed transaction.
module m9_recovery_cdc_bridge #(
    parameter integer RESET_GUARD_CYCLES=6
) (
    input wire health_clk,input wire health_rst,input wire health_cold_rst,
    input wire health_recovery_start,
    input wire sys_clk,input wire sys_rst,input wire sys_cold_rst,
    output wire sys_recovery_start,
    input wire sys_recovery_complete,input wire sys_recovery_failed,
    input wire sys_recovery_progress,
    output wire health_recovery_complete,
    output wire health_recovery_failed,
    output wire health_recovery_progress
);
    wire sys_recovery_start_raw;
    wire health_recovery_complete_raw;
    wire health_recovery_failed_raw;
    wire health_recovery_progress_raw;
    reg sys_transaction_armed;
    reg health_transaction_armed;
    (* ASYNC_REG = "TRUE" *) reg [RESET_GUARD_CYCLES-1:0] start_reset_guard;
    (* ASYNC_REG = "TRUE" *) reg [RESET_GUARD_CYCLES-1:0] result_reset_guard;
    wire health_reset_sys;
    wire sys_reset_health;

    // Peer resets are levels, not asynchronous controls in the opposite
    // domain. Each is contained by a normal two-stage destination synchronizer
    // before it reloads the local replay guard.
    cdc_bit_sync u_health_reset_sys_sync(
        .clk_dst(sys_clk),.rst_dst(sys_rst),.async_in(health_rst),
        .sync_out(health_reset_sys));
    cdc_bit_sync u_sys_reset_health_sync(
        .clk_dst(health_clk),.rst_dst(health_rst),.async_in(sys_rst),
        .sync_out(sys_reset_health));

    wire start_ready=!start_reset_guard[RESET_GUARD_CYCLES-1];
    wire results_ready=!result_reset_guard[RESET_GUARD_CYCLES-1];
    wire sys_complete_qualified=sys_recovery_complete && sys_transaction_armed;
    wire sys_failed_qualified=sys_recovery_failed && sys_transaction_armed;
    wire sys_progress_qualified=sys_recovery_progress && sys_transaction_armed;

    assign sys_recovery_start=sys_recovery_start_raw && start_ready;
    assign health_recovery_complete=health_recovery_complete_raw &&
                                    results_ready && health_transaction_armed;
    assign health_recovery_failed=health_recovery_failed_raw &&
                                  results_ready && health_transaction_armed;
    assign health_recovery_progress=health_recovery_progress_raw &&
                                    results_ready && health_transaction_armed;

    initial begin
        if(RESET_GUARD_CYCLES<2) begin
            $display("M9_RECOVERY_CDC_CONFIG_ERROR RESET_GUARD_CYCLES must be at least two");
            $finish;
        end
    end

    // Either reset can change one side of a toggle independently. Hold the
    // consumer closed long enough to capture the new stable parity baseline.
    always @(posedge sys_clk or posedge sys_rst) begin
        if(sys_rst)
            start_reset_guard<={RESET_GUARD_CYCLES{1'b1}};
        else if(health_reset_sys)
            start_reset_guard<={RESET_GUARD_CYCLES{1'b1}};
        else
            start_reset_guard<={start_reset_guard[RESET_GUARD_CYCLES-2:0],1'b0};
    end

    always @(posedge health_clk or posedge health_rst) begin
        if(health_rst)
            result_reset_guard<={RESET_GUARD_CYCLES{1'b1}};
        else if(sys_reset_health)
            result_reset_guard<={RESET_GUARD_CYCLES{1'b1}};
        else
            result_reset_guard<={result_reset_guard[RESET_GUARD_CYCLES-2:0],1'b0};
    end

    // A reset in either domain aborts the bridge transaction. The Health
    // policy remains fail-closed and can issue a fresh request after timeout.
    always @(posedge sys_clk or posedge sys_rst) begin
        if(sys_rst)
            sys_transaction_armed<=1'b0;
        else if(start_reset_guard[RESET_GUARD_CYCLES-1])
            sys_transaction_armed<=1'b0;
        else if(sys_recovery_start)
            sys_transaction_armed<=1'b1;
        else if(sys_complete_qualified || sys_failed_qualified)
            sys_transaction_armed<=1'b0;
    end

    always @(posedge health_clk or posedge health_rst) begin
        if(health_rst)
            health_transaction_armed<=1'b0;
        else if(health_recovery_start)
            health_transaction_armed<=1'b1;
        else if(result_reset_guard[RESET_GUARD_CYCLES-1])
            health_transaction_armed<=1'b0;
        else if((health_recovery_complete_raw || health_recovery_failed_raw) &&
                results_ready && health_transaction_armed)
            health_transaction_armed<=1'b0;
    end

    m9_recovery_event_toggle u_start_event (
        .src_clk(health_clk),.src_rst(health_rst),
        .src_cold_rst(health_cold_rst),.src_event(health_recovery_start),
        .dst_clk(sys_clk),.dst_rst(sys_rst),
        .dst_pulse(sys_recovery_start_raw)
    );
    m9_recovery_event_toggle u_complete_event (
        .src_clk(sys_clk),.src_rst(sys_rst),
        .src_cold_rst(sys_cold_rst),.src_event(sys_complete_qualified),
        .dst_clk(health_clk),.dst_rst(health_rst),
        .dst_pulse(health_recovery_complete_raw)
    );
    m9_recovery_event_toggle u_failed_event (
        .src_clk(sys_clk),.src_rst(sys_rst),
        .src_cold_rst(sys_cold_rst),.src_event(sys_failed_qualified),
        .dst_clk(health_clk),.dst_rst(health_rst),
        .dst_pulse(health_recovery_failed_raw)
    );
    m9_recovery_event_toggle u_progress_event (
        .src_clk(sys_clk),.src_rst(sys_rst),
        .src_cold_rst(sys_cold_rst),.src_event(sys_progress_qualified),
        .dst_clk(health_clk),.dst_rst(health_rst),
        .dst_pulse(health_recovery_progress_raw)
    );
endmodule


// Recovery event parity belongs to the A2 power epoch, not to either
// independently reset functional domain. Functional reset suppresses new
// source events without changing parity; destination-local reset still clears
// and re-baselines the receive chain behind its replay guard.
module m9_recovery_event_toggle (
    input wire src_clk,input wire src_rst,input wire src_cold_rst,
    input wire src_event,
    input wire dst_clk,input wire dst_rst,
    output reg dst_pulse
);
    reg src_toggle;
    (* ASYNC_REG = "TRUE" *) reg dst_sync_stage1;
    (* ASYNC_REG = "TRUE" *) reg dst_sync_stage2;
    reg dst_seen_toggle;

    always @(posedge src_clk or posedge src_cold_rst) begin
        if(src_cold_rst)
            src_toggle<=1'b0;
        else if(!src_rst && src_event)
            src_toggle<=~src_toggle;
    end

    always @(posedge dst_clk or posedge dst_rst) begin
        if(dst_rst) begin
            dst_sync_stage1<=1'b0;
            dst_sync_stage2<=1'b0;
            dst_seen_toggle<=1'b0;
            dst_pulse<=1'b0;
        end else begin
            dst_sync_stage1<=src_toggle;
            dst_sync_stage2<=dst_sync_stage1;
            dst_seen_toggle<=dst_sync_stage2;
            dst_pulse<=dst_sync_stage2 ^ dst_seen_toggle;
        end
    end
endmodule
