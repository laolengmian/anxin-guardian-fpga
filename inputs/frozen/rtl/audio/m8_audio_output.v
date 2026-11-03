// The event bridge commits at pre_valid. Capture that education sample here;
// on the following clock both tone and mixer see its newly committed bundle.
// Normal/inactive retains all 24 diagnostic bits, not just the PCM16 slice.
module m8_audio_output (
    input wire clk,input wire rst,input wire pre_valid,
    input wire [23:0] pre_left,input wire [23:0] pre_right,
    input wire event_active,input wire [1:0] event_level,
    input wire [7:0] event_id,input wire [7:0] event_epoch,
    output wire out_valid,output wire [23:0] out_left,output wire [23:0] out_right
);
    reg sample_valid_q;
    reg [23:0] sample_left_q,sample_right_q,normal_left_q,normal_right_q;
    reg normal_q;
    wire signed [15:0] alert_pcm,mixed_pcm;
    wire signed [15:0] education_pcm=$signed(sample_left_q[23:8]);
    m8_alert_tone u_alert (
        .clk(clk),.rst(rst),.sample_valid(sample_valid_q),
        .event_active(event_active),.event_level(event_level),
        .event_id(event_id),.event_epoch(event_epoch),.alert_pcm(alert_pcm));
    m8_audio_arbiter u_mix (
        .clk(clk),.rst(rst),.in_valid(sample_valid_q),
        .education_pcm(education_pcm),.alert_pcm(alert_pcm),
        .event_active(event_active),.event_level(event_level),
        .out_valid(out_valid),.out_pcm(mixed_pcm));
    assign out_left=normal_q ? normal_left_q : {mixed_pcm,8'd0};
    assign out_right=normal_q ? normal_right_q : {mixed_pcm,8'd0};
    always @(posedge clk or posedge rst) begin
        if(rst) begin
            sample_valid_q<=0;sample_left_q<=0;sample_right_q<=0;
            normal_q<=1;normal_left_q<=0;normal_right_q<=0;
        end else begin
            sample_valid_q<=pre_valid;
            if(pre_valid) begin sample_left_q<=pre_left;sample_right_q<=pre_right;end
            if(sample_valid_q) begin
                normal_q<=!event_active || event_level==2'd0;
                normal_left_q<=sample_left_q;normal_right_q<=sample_right_q;
            end
        end
    end
endmodule
