// Deterministic, fictional demo cues at the inherited nominal 48 kHz cadence.
// Warning: 1 kHz, 200 ms per second. Emergency: 2 kHz, 125 ms on/off.
// Combinational PCM describes the sample about to be consumed; all counters
// advance only on sample_valid. Any applied bundle change restarts at phase 0.
module m8_alert_tone (
    input wire clk,input wire rst,input wire sample_valid,
    input wire event_active,input wire [1:0] event_level,
    input wire [7:0] event_id,input wire [7:0] event_epoch,
    output wire signed [15:0] alert_pcm
);
    localparam [1:0] WARNING=2'd1,EMERGENCY=2'd2;
    localparam [15:0] WARNING_PERIOD=16'd48000,WARNING_ON=16'd9600;
    localparam [15:0] EMERGENCY_PERIOD=16'd12000,EMERGENCY_ON=16'd6000;
    localparam [5:0] WARNING_HALF=6'd24,EMERGENCY_HALF=6'd12;
    localparam signed [15:0] WARNING_AMPLITUDE=16'sd4096;
    localparam signed [15:0] EMERGENCY_AMPLITUDE=16'sd8192;
    reg active_q,negative_q;
    reg [1:0] level_q;
    reg [7:0] id_q,epoch_q;
    reg [15:0] cadence_q;
    reg [5:0] half_q;
    wire is_emergency=event_level==EMERGENCY;
    wire enabled=event_active && (event_level==WARNING || is_emergency);
    wire restart=event_active!=active_q || event_level!=level_q ||
                 event_id!=id_q || event_epoch!=epoch_q;
    wire [15:0] cadence=restart ? 16'd0 : cadence_q;
    wire [5:0] half_count=restart ? 6'd0 : half_q;
    wire negative=restart ? 1'b0 : negative_q;
    wire [15:0] period=is_emergency ? EMERGENCY_PERIOD : WARNING_PERIOD;
    wire [15:0] on_count=is_emergency ? EMERGENCY_ON : WARNING_ON;
    wire [5:0] half_period=is_emergency ? EMERGENCY_HALF : WARNING_HALF;
    wire signed [15:0] amplitude=is_emergency ? EMERGENCY_AMPLITUDE : WARNING_AMPLITUDE;
    assign alert_pcm=!rst && sample_valid && enabled && cadence<on_count ?
                     (negative ? -amplitude : amplitude) : 16'sd0;
    always @(posedge clk or posedge rst) begin
        if(rst) begin
            active_q<=0;level_q<=0;id_q<=0;epoch_q<=0;
            cadence_q<=0;half_q<=0;negative_q<=0;
        end else if(sample_valid) begin
            active_q<=event_active;level_q<=event_level;
            id_q<=event_id;epoch_q<=event_epoch;
            if(!enabled) begin cadence_q<=0;half_q<=0;negative_q<=0;end
            else begin
                cadence_q<=cadence==period-1'b1 ? 16'd0 : cadence+1'b1;
                if(half_count==half_period-1'b1) begin
                    half_q<=0;negative_q<=~negative;
                end else begin half_q<=half_count+1'b1;negative_q<=negative;end
            end
        end
    end
endmodule
