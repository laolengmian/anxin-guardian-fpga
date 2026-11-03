// M8-C one registered sample boundary: signed ducking, extended addition,
// then saturation. Invalid cycles hold the last PCM and do not change mode.
module m8_audio_arbiter (
    input wire clk,input wire rst,input wire in_valid,
    input wire signed [15:0] education_pcm,input wire signed [15:0] alert_pcm,
    input wire event_active,input wire [1:0] event_level,
    output reg out_valid,output reg signed [15:0] out_pcm
);
    localparam [1:0] WARNING=2'd1,EMERGENCY=2'd2,SAFE=2'd3;
    localparam signed [17:0] PCM_MAX=18'sd32767,PCM_MIN=-18'sd32768;
    wire signed [17:0] education_extended={{2{education_pcm[15]}},education_pcm};
    wire signed [17:0] alert_extended={{2{alert_pcm[15]}},alert_pcm};
    reg signed [17:0] ducked,mixed;
    reg signed [15:0] saturated;
    always @(*) begin
        ducked=education_extended;
        if(event_active && event_level==WARNING) ducked=education_extended>>>2;
        if(event_active && event_level==EMERGENCY) ducked=education_extended>>>3;
        mixed=ducked;
        if(event_active && (event_level==WARNING || event_level==EMERGENCY))
            mixed=ducked+alert_extended;
        // Reserved SAFE input is silent; M9 owns the upstream pause policy.
        if(event_active && event_level==SAFE) mixed=18'sd0;
        if(mixed>PCM_MAX) saturated=16'sh7fff;
        else if(mixed<PCM_MIN) saturated=16'sh8000;
        else saturated=mixed[15:0];
    end
    always @(posedge clk or posedge rst) begin
        if(rst) begin out_valid<=0;out_pcm<=0;end
        else begin
            out_valid<=in_valid;
            if(in_valid) out_pcm<=saturated;
        end
    end
endmodule
