// Keep the inherited I2S tick alive independently of a PCM epoch reset. The
// WAV player registers its new sample on this same tick edge. Register tone
// and source selection here so both alternatives describe that same sample.
module m7b_audio_boundary (
    input wire clk,input wire rst,input wire sample_tick,input wire use_wav,
    input wire [23:0] tone_left,input wire [23:0] tone_right,
    input wire [23:0] wav_left,input wire [23:0] wav_right,
    output reg audio_valid,output wire [23:0] audio_left,output wire [23:0] audio_right
);
    reg selected_wav;
    reg [23:0] tone_left_q,tone_right_q;
    always @(posedge clk or posedge rst) begin
        if(rst) begin audio_valid<=0;selected_wav<=0;tone_left_q<=0;tone_right_q<=0;end
        else begin
            audio_valid<=sample_tick;
            if(sample_tick) begin
                selected_wav<=use_wav;tone_left_q<=tone_left;tone_right_q<=tone_right;
            end
        end
    end
    assign audio_left=selected_wav ? wav_left : tone_left_q;
    assign audio_right=selected_wav ? wav_right : tone_right_q;
endmodule
