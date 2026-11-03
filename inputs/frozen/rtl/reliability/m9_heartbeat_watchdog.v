// Health-domain watchdog for an asynchronous heartbeat toggle. Reset and
// disabled windows align epochs without treating an old toggle as liveness.
module m9_heartbeat_watchdog #(
    parameter integer TIMEOUT_CYCLES=5000000
) (
    input wire clk,input wire rst,input wire expect_heartbeat,
    input wire async_toggle,
    output reg heartbeat_pulse,output reg alive,
    output reg timeout_pulse,output reg timeout_active
);
    localparam integer COUNT_WIDTH=(TIMEOUT_CYCLES<=1) ? 1 :
                                   $clog2(TIMEOUT_CYCLES);
    (* ASYNC_REG="TRUE" *) reg sync_stage1;
    (* ASYNC_REG="TRUE" *) reg sync_stage2;
    reg seen_toggle;
    reg [COUNT_WIDTH-1:0] timeout_count;
    reg [1:0] init_count;
    reg initialized;

    always @(posedge clk or posedge rst) begin
        if(rst) begin
            sync_stage1<=0;sync_stage2<=0;seen_toggle<=0;
            timeout_count<=0;init_count<=0;initialized<=0;
            heartbeat_pulse<=0;alive<=0;timeout_pulse<=0;timeout_active<=0;
        end else begin
            sync_stage1<=async_toggle;
            sync_stage2<=sync_stage1;
            heartbeat_pulse<=0;
            timeout_pulse<=0;
            if(!initialized) begin
                seen_toggle<=sync_stage2;
                timeout_count<=0;alive<=0;timeout_active<=0;
                if(init_count==2'd3) initialized<=1;
                else init_count<=init_count+1'b1;
            end else if(!expect_heartbeat) begin
                seen_toggle<=sync_stage2; // align while disabled
                timeout_count<=0;alive<=0;timeout_active<=0;
            end else if(sync_stage2!=seen_toggle) begin
                seen_toggle<=sync_stage2;
                timeout_count<=0;
                heartbeat_pulse<=1;
                alive<=1;
                timeout_active<=0;
            end else if(timeout_active) begin
                alive<=0;
            end else if(TIMEOUT_CYCLES<=1 || timeout_count>=TIMEOUT_CYCLES-1) begin
                timeout_count<=0;
                timeout_pulse<=1;
                timeout_active<=1;
                alive<=0;
            end else begin
                timeout_count<=timeout_count+1'b1;
            end
        end
    end
endmodule
