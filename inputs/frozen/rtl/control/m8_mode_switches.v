// M8 board-mode input: two synchronized active-high switches select a stable
// NORMAL/WARNING/EMERGENCY event record. SAFE remains reserved for M9.
module m8_mode_switches #(
    parameter integer STABLE_CYCLES=100000
) (
    input wire clk,
    input wire rst,
    input wire sw_warning_async,
    input wire sw_emergency_async,
    (* preserve = "true" *) output reg event_update,
    (* preserve = "true" *) output reg event_active,
    (* preserve = "true" *) output reg [1:0] event_level,
    (* preserve = "true" *) output reg [7:0] event_id,
    (* preserve = "true" *) output reg [7:0] event_epoch
);
    localparam [1:0] LEVEL_NORMAL=2'd0;
    localparam [1:0] LEVEL_WARNING=2'd1;
    localparam [1:0] LEVEL_EMERGENCY=2'd2;

    // TD packs direct board inputs into IOB registers. ASYNC_REG on these
    // direct-input stages produces undriven synthetic IOB-clock warnings in
    // TD 6.2, so this follows the routed KEY2/KEY4 two-register pattern.
    reg warning_sync1;
    (* preserve = "true" *) reg warning_sync2;
    reg emergency_sync1;
    (* preserve = "true" *) reg emergency_sync2;
    reg [1:0] candidate_level;
    reg [31:0] stable_count;

    wire [1:0] synchronized_level=emergency_sync2 ? LEVEL_EMERGENCY :
                                  warning_sync2 ? LEVEL_WARNING : LEVEL_NORMAL;

    always @(posedge clk or posedge rst) begin
        if(rst) begin
            warning_sync1<=0;warning_sync2<=0;
            emergency_sync1<=0;emergency_sync2<=0;
            candidate_level<=LEVEL_NORMAL;stable_count<=0;
            event_update<=0;event_active<=0;event_level<=LEVEL_NORMAL;
            event_id<=0;event_epoch<=0;
        end else begin
            warning_sync1<=sw_warning_async;
            warning_sync2<=warning_sync1;
            emergency_sync1<=sw_emergency_async;
            emergency_sync2<=emergency_sync1;
            event_update<=0;

            if(synchronized_level!=candidate_level) begin
                candidate_level<=synchronized_level;
                stable_count<=32'd1;
                if(STABLE_CYCLES<=1) begin
                    event_active<=synchronized_level!=LEVEL_NORMAL;
                    event_level<=synchronized_level;
                    event_id<={6'd0,synchronized_level};
                    event_epoch<=event_epoch+1'b1;
                    event_update<=1;
                    stable_count<=0;
                end
            end else if(synchronized_level!=event_level) begin
                if(stable_count>=STABLE_CYCLES-1) begin
                    event_active<=synchronized_level!=LEVEL_NORMAL;
                    event_level<=synchronized_level;
                    event_id<={6'd0,synchronized_level};
                    event_epoch<=event_epoch+1'b1;
                    event_update<=1;
                    stable_count<=0;
                end else begin
                    stable_count<=stable_count+1'b1;
                end
            end else begin
                stable_count<=0;
            end
        end
    end
endmodule
