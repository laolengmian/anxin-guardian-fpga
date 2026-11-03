// Toggle once per bounded number of final HDMI audio samples. Only sample_valid
// advances the cadence; Bank-WAV consumption is deliberately not used here.
module m9_audio_heartbeat #(
    parameter integer SAMPLES_PER_HEARTBEAT=480
) (
    input wire clk,input wire rst,input wire sample_valid,
    output reg heartbeat_toggle,output reg heartbeat_pulse
);
    localparam integer COUNT_WIDTH=(SAMPLES_PER_HEARTBEAT<=1) ? 1 :
                                   $clog2(SAMPLES_PER_HEARTBEAT);
    reg [COUNT_WIDTH-1:0] sample_count;
    always @(posedge clk or posedge rst) begin
        if(rst) begin
            sample_count<=0;
            heartbeat_toggle<=0;
            heartbeat_pulse<=0;
        end else begin
            heartbeat_pulse<=0;
            if(sample_valid) begin
                if(SAMPLES_PER_HEARTBEAT<=1 ||
                   sample_count>=SAMPLES_PER_HEARTBEAT-1) begin
                    sample_count<=0;
                    heartbeat_toggle<=~heartbeat_toggle;
                    heartbeat_pulse<=1;
                end else begin
                    sample_count<=sample_count+1'b1;
                end
            end
        end
    end
endmodule
