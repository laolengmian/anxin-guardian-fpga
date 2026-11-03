// M9-private equivalent of the frozen diagnostic cue timeline.
// All cue/progress thresholds fit in 16 bits. Share the high-word test,
// but keep the full 32-bit count: expired cues must never wrap and reappear.
module m9_subtitle_timeline (
    input wire clk,input wire rst,input wire clip_ready,input wire [1:0] clip_id,
    input wire epoch_clear,input wire education_advance,
    input wire [31:0] played_sample_count,
    output reg content_active,output reg cue_valid,
    output reg [7:0] cue_index,output reg [7:0] text_id,
    output reg [1:0] style_id,output reg [3:0] progress_step
);
    wire [15:0] n=played_sample_count[15:0];
    wire in_cue_range=played_sample_count[31:16]==0;
    reg [7:0] selected_text;
    reg [3:0] selected_progress;
    always @(*) begin
        selected_text=0;
        if(in_cue_range) begin
            case(clip_id)
                0:if(n>16'd2400 && n<=16'd24000) selected_text=1;
                1:begin
                    if(n>16'd2400 && n<=16'd13200) selected_text=1;
                    else if(n>16'd18000 && n<=16'd28800) selected_text=2;
                end
                2:begin
                    if(n>16'd2400 && n<=16'd9600) selected_text=1;
                    else if(n>16'd12800 && n<=16'd20000) selected_text=2;
                    else if(n>16'd23200 && n<=16'd30400) selected_text=3;
                end
                3:begin
                    if(n>16'd2400 && n<=16'd7800) selected_text=1;
                    else if(n>16'd10200 && n<=16'd15600) selected_text=2;
                    else if(n>16'd18000 && n<=16'd23400) selected_text=3;
                    else if(n>16'd25800 && n<=16'd31200) selected_text=4;
                end
            endcase
        end
        if(!in_cue_range || n>=16'd38400) selected_progress=8;
        else if(n>=16'd33600) selected_progress=7;
        else if(n>=16'd28800) selected_progress=6;
        else if(n>=16'd24000) selected_progress=5;
        else if(n>=16'd19200) selected_progress=4;
        else if(n>=16'd14400) selected_progress=3;
        else if(n>=16'd9600) selected_progress=2;
        else if(n>=16'd4800) selected_progress=1;
        else selected_progress=0;
    end
    always @(posedge clk or posedge rst) begin
        if(rst) begin
            content_active<=0;cue_valid<=0;cue_index<=0;text_id<=0;
            style_id<=0;progress_step<=0;
        end else if(epoch_clear || !clip_ready) begin
            content_active<=0;cue_valid<=0;cue_index<=0;text_id<=0;
            style_id<=0;progress_step<=0;
        end else if(education_advance && played_sample_count!=0) begin
            content_active<=1;cue_valid<=selected_text!=0;
            cue_index<=selected_text==0 ? 8'd0 : selected_text-1'b1;
            text_id<=selected_text;style_id<=0;progress_step<=selected_progress;
        end
    end
endmodule
