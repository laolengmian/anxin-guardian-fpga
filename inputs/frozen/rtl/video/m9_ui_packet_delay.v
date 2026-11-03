// Preserve the retired Health renderer delay; A-Fast selects one stage in production.
module m9_ui_packet_delay #(
    parameter integer STAGES=3
) (
    input wire clk,input wire rst,input wire in_valid,input wire in_user,input wire in_last,
    input wire [14:0] in_x,input wire [14:0] in_y,input wire [23:0] in_rgb,
    output wire out_valid,output wire out_user,output wire out_last,
    output wire [14:0] out_x,output wire [14:0] out_y,output wire [23:0] out_rgb
);
    wire [56:0] in_packet={in_valid,in_user,in_last,in_x,in_y,in_rgb};
    wire [56:0] out_packet;
    assign {out_valid,out_user,out_last,out_x,out_y,out_rgb}=out_packet;

    generate if(STAGES==1) begin:g_one_stage
        reg [56:0] stage1;
        assign out_packet=stage1;
        always @(posedge clk or posedge rst) begin
            if(rst) stage1<=0;
            else stage1<=in_packet;
        end
    end else begin:g_three_stages
        reg [56:0] stage1,stage2,stage3;
        assign out_packet=stage3;
        always @(posedge clk or posedge rst) begin
            if(rst) begin stage1<=0;stage2<=0;stage3<=0;end
            else begin stage1<=in_packet;stage2<=stage1;stage3<=stage2;end
        end
    end endgenerate
endmodule
