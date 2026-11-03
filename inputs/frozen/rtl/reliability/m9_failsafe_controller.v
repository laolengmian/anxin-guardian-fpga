// Independent Health-domain SAFE policy. Recovery control stays fail-closed:
// SAFE releases only after a verified completion clears the sticky fault and
// the monitor withdraws fault_request. MAX_RETRIES bounds repeated attempts.
module m9_failsafe_controller #(
    parameter integer RETRY_DELAY_CYCLES=50000000,
    parameter integer RECOVERY_TIMEOUT_CYCLES=250000000,
    parameter integer TIMER_TICK_CYCLES=1,
    parameter integer MAX_RETRIES=3
) (
    input wire clk,input wire rst,input wire timer_tick,input wire boot_ready,
    input wire fault_request,input wire recoverable,
    input wire recovery_complete,input wire recovery_failed,
    input wire recovery_progress,
    output reg [1:0] state,output wire [7:0] retry_count,
    output wire safe_pause,output wire recovery_active,
    output reg recovery_start,output reg clear_sticky
);
    localparam [1:0] BOOT=2'd0,NORMAL=2'd1,SAFE=2'd2,RECOVER=2'd3;
    localparam integer RETRY_WIDTH=MAX_RETRIES<=1 ? 1 :
                                   $clog2(MAX_RETRIES+1);
    localparam integer RETRY_USES_RAW=TIMER_TICK_CYCLES<=1 ||
        RETRY_DELAY_CYCLES<=TIMER_TICK_CYCLES;
    localparam integer TIMEOUT_USES_RAW=TIMER_TICK_CYCLES<=1 ||
        RECOVERY_TIMEOUT_CYCLES<=TIMER_TICK_CYCLES;
    // When a shared tick is used, include its unknown starting phase so the
    // elapsed wall-clock interval can never be shorter than the cycle limit.
    localparam integer RETRY_DELAY_TICKS=RETRY_USES_RAW ? RETRY_DELAY_CYCLES :
        ((RETRY_DELAY_CYCLES-2)/TIMER_TICK_CYCLES)+2;
    localparam integer RECOVERY_TIMEOUT_TICKS=TIMEOUT_USES_RAW ?
        RECOVERY_TIMEOUT_CYCLES :
        ((RECOVERY_TIMEOUT_CYCLES-2)/TIMER_TICK_CYCLES)+2;
    localparam integer MAX_TIMER_TICKS=
        RETRY_DELAY_TICKS>RECOVERY_TIMEOUT_TICKS ?
        RETRY_DELAY_TICKS : RECOVERY_TIMEOUT_TICKS;
    localparam integer TIMER_WIDTH=MAX_TIMER_TICKS<=1 ? 1 :
                                   $clog2(MAX_TIMER_TICKS);
    reg [TIMER_WIDTH-1:0] timer_count;
    reg [RETRY_WIDTH-1:0] retry_count_value;
    reg recovery_verified;
    reg recovery_progress_q;
    wire recovery_progress_event=recovery_progress && !recovery_progress_q;
    wire retry_timer_step=RETRY_USES_RAW || timer_tick;
    wire recovery_timer_step=TIMEOUT_USES_RAW || timer_tick;

    assign retry_count={{(8-RETRY_WIDTH){1'b0}},retry_count_value};
    assign safe_pause=state[1];
    assign recovery_active=state==RECOVER;

    always @(posedge clk) begin
        if(rst) begin
            state<=BOOT;retry_count_value<=0;timer_count<=0;
            recovery_verified<=0;recovery_progress_q<=0;
            recovery_start<=0;clear_sticky<=0;
        end else begin
            recovery_start<=0;
            clear_sticky<=0;
            recovery_progress_q<=recovery_progress;
            case(state)
                BOOT:begin
                    retry_count_value<=0;timer_count<=0;recovery_verified<=0;
                    if(fault_request) state<=SAFE;
                    else if(boot_ready) state<=NORMAL;
                end
                NORMAL:begin
                    retry_count_value<=0;timer_count<=0;recovery_verified<=0;
                    if(fault_request) state<=SAFE;
                end
                SAFE:begin
                    recovery_verified<=0;
                    if(recoverable && retry_count_value<MAX_RETRIES) begin
                        if(RETRY_DELAY_TICKS<=1 ||
                           (retry_timer_step &&
                            timer_count>=RETRY_DELAY_TICKS-1)) begin
                            state<=RECOVER;timer_count<=0;
                            retry_count_value<=retry_count_value+1'b1;
                            recovery_start<=1;
                        end else if(retry_timer_step)
                            timer_count<=timer_count+1'b1;
                    end else timer_count<=0;
                end
                RECOVER:begin
                    if(recovery_failed) begin
                        state<=SAFE;timer_count<=0;recovery_verified<=0;
                    end else if(recovery_complete && !recovery_verified) begin
                        clear_sticky<=1;recovery_verified<=1;timer_count<=0;
                    end else if(recovery_verified && !fault_request && boot_ready) begin
                        state<=NORMAL;retry_count_value<=0;timer_count<=0;
                        recovery_verified<=0;
                    end else if(!recoverable) begin
                        state<=SAFE;timer_count<=0;recovery_verified<=0;
                    end else if(recovery_progress_event) begin
                        timer_count<=0;
                    end else if(RECOVERY_TIMEOUT_TICKS<=1 ||
                                (recovery_timer_step &&
                                 timer_count>=RECOVERY_TIMEOUT_TICKS-1)) begin
                        state<=SAFE;timer_count<=0;recovery_verified<=0;
                    end else if(recovery_timer_step) begin
                        timer_count<=timer_count+1'b1;
                    end
                end
                default:begin
                    state<=SAFE;timer_count<=0;recovery_verified<=0;
                end
            endcase
        end
    end
endmodule
