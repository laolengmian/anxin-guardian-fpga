// U6-V1 formal Product timeline. Historical short diagnostic timeline remains
// in m9_subtitle_timeline.v as a frozen regression oracle.
module m9_product_subtitle_timeline (
    input wire clk,input wire rst,input wire clip_ready,input wire [1:0] clip_id,
    input wire epoch_clear,input wire education_advance,
    input wire [31:0] played_sample_count,
    output reg content_active,output reg cue_valid,
    output reg [7:0] cue_index,output reg [7:0] text_id,
    output reg [1:0] style_id,output reg [3:0] progress_step
);
    reg selected_valid;
    reg [7:0] selected_index,selected_text;

    always @(*) begin
        selected_valid=1'b0;
        selected_index=8'd0;
        selected_text=8'd0;
        case(clip_id)
            2'd0:begin
                if(played_sample_count>=32'd20160 && played_sample_count<32'd96480) begin
                    selected_valid=1'b1;selected_index=8'd0;selected_text=8'd1;
                end else if(played_sample_count>=32'd131040 && played_sample_count<32'd173280) begin
                    selected_valid=1'b1;selected_index=8'd1;selected_text=8'd2;
                end else if(played_sample_count>=32'd209760 && played_sample_count<32'd256800) begin
                    selected_valid=1'b1;selected_index=8'd2;selected_text=8'd3;
                end
            end
            2'd1:begin
                if(played_sample_count>=32'd22080 && played_sample_count<32'd74880) begin
                    selected_valid=1'b1;selected_index=8'd0;selected_text=8'd4;
                end else if(played_sample_count>=32'd105600 && played_sample_count<32'd144960) begin
                    selected_valid=1'b1;selected_index=8'd1;selected_text=8'd5;
                end else if(played_sample_count>=32'd183840 && played_sample_count<32'd236640) begin
                    selected_valid=1'b1;selected_index=8'd2;selected_text=8'd6;
                end
            end
            2'd2:begin
                if(played_sample_count>=32'd21120 && played_sample_count<32'd78720) begin
                    selected_valid=1'b1;selected_index=8'd0;selected_text=8'd7;
                end else if(played_sample_count>=32'd110400 && played_sample_count<32'd189600) begin
                    selected_valid=1'b1;selected_index=8'd1;selected_text=8'd8;
                end else if(played_sample_count>=32'd237600 && played_sample_count<32'd288480) begin
                    selected_valid=1'b1;selected_index=8'd2;selected_text=8'd9;
                end
            end
            2'd3:begin
                if(played_sample_count>=32'd28800 && played_sample_count<32'd73920) begin
                    selected_valid=1'b1;selected_index=8'd0;selected_text=8'd10;
                end else if(played_sample_count>=32'd102720 && played_sample_count<32'd210240) begin
                    selected_valid=1'b1;selected_index=8'd1;selected_text=8'd11;
                end else if(played_sample_count>=32'd246240 && played_sample_count<32'd304800) begin
                    selected_valid=1'b1;selected_index=8'd2;selected_text=8'd12;
                end
            end
        endcase
    end

    always @(posedge clk or posedge rst) begin
        if(rst) begin
            content_active<=1'b0;cue_valid<=1'b0;cue_index<=8'd0;text_id<=8'd0;
            style_id<=2'd0;progress_step<=4'd0;
        end else if(epoch_clear || !clip_ready) begin
            content_active<=1'b0;cue_valid<=1'b0;cue_index<=8'd0;text_id<=8'd0;
            style_id<=2'd0;progress_step<=4'd0;
        end else if(education_advance && played_sample_count!=0) begin
            content_active<=1'b1;cue_valid<=selected_valid;
            cue_index<=selected_valid ? selected_index : 8'd0;
            text_id<=selected_valid ? selected_text : 8'd0;
            style_id<=2'd0;progress_step<=4'd0;
        end
    end
endmodule
