// M9-C keeps the media and HDMI domains independently observable. A lock loss
// asynchronously withdraws only that domain's release; each lock must then stay
// stable for the full qualification interval before its reset can be released.
module m9_split_lock_qualifier #(
    parameter integer LOCK_STABLE_CYCLES=1000000,
    parameter integer TIMER_TICK_CYCLES=1
) (
    input wire clk_50m,input wire ext_rst_n,input wire timer_tick,
    input wire sys_pll_lock,input wire video_pll_lock,
    output reg sys_ready,output reg video_ready
);
    localparam integer USES_RAW=TIMER_TICK_CYCLES<=1 ||
        LOCK_STABLE_CYCLES<=TIMER_TICK_CYCLES;
    localparam integer LOCK_STABLE_TICKS=USES_RAW ? LOCK_STABLE_CYCLES :
        ((LOCK_STABLE_CYCLES-2)/TIMER_TICK_CYCLES)+2;
    localparam integer COUNT_WIDTH=LOCK_STABLE_TICKS<=1 ? 1 :
                                   $clog2(LOCK_STABLE_TICKS);
    wire timer_step=USES_RAW || timer_tick;
    wire sys_fault_async=~ext_rst_n || ~sys_pll_lock;
    wire video_fault_async=~ext_rst_n || ~video_pll_lock;

    (* ASYNC_REG = "TRUE" *) reg sys_sync1,sys_sync2;
    (* ASYNC_REG = "TRUE" *) reg video_sync1,video_sync2;
    reg [COUNT_WIDTH-1:0] sys_count,video_count;

    always @(posedge clk_50m or posedge sys_fault_async) begin
        if(sys_fault_async) begin
            sys_sync1<=0;sys_sync2<=0;
        end else begin
            sys_sync1<=sys_pll_lock;sys_sync2<=sys_sync1;
        end
    end
    always @(posedge clk_50m or posedge video_fault_async) begin
        if(video_fault_async) begin
            video_sync1<=0;video_sync2<=0;
        end else begin
            video_sync1<=video_pll_lock;video_sync2<=video_sync1;
        end
    end

    always @(posedge clk_50m or posedge sys_fault_async) begin
        if(sys_fault_async) begin
            sys_count<=0;sys_ready<=0;
        end else if(!sys_sync2) begin
            sys_count<=0;sys_ready<=0;
        end else if(!sys_ready && timer_step) begin
            if(LOCK_STABLE_TICKS<=1 || sys_count>=LOCK_STABLE_TICKS-1)
                sys_ready<=1;
            else sys_count<=sys_count+1'b1;
        end
    end
    always @(posedge clk_50m or posedge video_fault_async) begin
        if(video_fault_async) begin
            video_count<=0;video_ready<=0;
        end else if(!video_sync2) begin
            video_count<=0;video_ready<=0;
        end else if(!video_ready && timer_step) begin
            if(LOCK_STABLE_TICKS<=1 || video_count>=LOCK_STABLE_TICKS-1)
                video_ready<=1;
            else video_count<=video_count+1'b1;
        end
    end
endmodule
