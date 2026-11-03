// M9 Product attention layer. Geometry, dimming and packet timing match M8-C;
// only the approved two-line U6 Chinese copy replaces the English bitmap.
module m9_product_attention_renderer (
    input wire clk,input wire rst,
    input wire in_valid,input wire in_user,input wire in_last,
    input wire [14:0] in_x,input wire [14:0] in_y,input wire [23:0] in_rgb,
    input wire event_active_pending,input wire [1:0] event_level_pending,
    input wire [7:0] event_id_pending,input wire [7:0] event_epoch_pending,
    output wire [6:0] u6_glyph_id,output wire [3:0] u6_glyph_row,
    input wire [15:0] u6_glyph_bits,
    output reg out_valid,output reg out_user,output reg out_last,
    output reg [14:0] out_x,output reg [14:0] out_y,output reg [23:0] out_rgb
);
    localparam [1:0] LEVEL_WARNING=2'd1,LEVEL_EMERGENCY=2'd2;
    localparam [23:0] WARNING_BORDER=24'hffd447;
    localparam [23:0] WARNING_BANNER=24'h5a4300;
    localparam [23:0] WARNING_TEXT=24'hfff4c2;
    localparam [23:0] WARNING_MARK=24'h1a1200;
    localparam [23:0] EMERGENCY_BORDER=24'hff3b30;
    localparam [23:0] EMERGENCY_BANNER=24'h760f18;
    localparam [23:0] EMERGENCY_TEXT=24'hfff1d6;
    localparam [6:0] BLANK_GLYPH=7'd127;

    reg event_active_q;
    reg [1:0] event_level_q;
    reg [7:0] event_id_q,event_epoch_q;
    wire first=in_valid && in_user;
    wire event_active=first ? event_active_pending : event_active_q;
    wire [1:0] event_level=first ? event_level_pending : event_level_q;
    wire in_canvas=(in_x[14:11]==0) && (in_y[14:10]==0);
    wire [10:0] pixel_x=in_x[10:0];
    wire [9:0] pixel_y=in_y[9:0];
    wire warning_active=event_active && event_level==LEVEL_WARNING && in_canvas;
    wire emergency_active=event_active && event_level==LEVEL_EMERGENCY && in_canvas;

    wire in_media=pixel_x>=11'd160 && pixel_x<11'd1120 && pixel_y<10'd720;
    wire [23:0] warning_dim={1'b0,in_rgb[23:17],1'b0,in_rgb[15:9],1'b0,in_rgb[7:1]};
    wire [23:0] emergency_dim={2'b0,in_rgb[23:18],2'b0,in_rgb[15:10],2'b0,in_rgb[7:2]};
    wire [23:0] base_rgb=warning_active && in_media ? warning_dim :
                           emergency_active && in_media ? emergency_dim : in_rgb;

    wire warning_outer=pixel_x>=11'd160 && pixel_x<11'd1120 && pixel_y>=10'd8 && pixel_y<10'd712;
    wire warning_inner=pixel_x>=11'd166 && pixel_x<11'd1114 && pixel_y>=10'd14 && pixel_y<10'd706;
    wire emergency_outer=pixel_x>=11'd160 && pixel_x<11'd1120 && pixel_y>=10'd4 && pixel_y<10'd716;
    wire emergency_inner=pixel_x>=11'd170 && pixel_x<11'd1110 && pixel_y>=10'd14 && pixel_y<10'd706;
    wire border_on=warning_active && warning_outer && !warning_inner ||
                   emergency_active && emergency_outer && !emergency_inner;
    wire banner_on=warning_active && pixel_x>=11'd400 && pixel_x<11'd880 && pixel_y>=10'd48 && pixel_y<10'd144 ||
                   emergency_active && pixel_x>=11'd320 && pixel_x<11'd960 && pixel_y>=10'd32 && pixel_y<10'd176;

    wire [5:0] warning_dx=pixel_x>=11'd456 ? pixel_x[5:0]-6'd8 : 6'd8-pixel_x[5:0];
    wire [4:0] warning_half=pixel_y[5:1];
    wire warning_icon=warning_active && pixel_x>=11'd425 && pixel_x<11'd488 &&
                      pixel_y>=10'd64 && pixel_y<10'd128 && warning_dx<=warning_half;
    wire warning_mark=warning_active &&
                      ((pixel_x>=11'd453 && pixel_x<11'd460 && pixel_y>=10'd82 && pixel_y<10'd108) ||
                       (pixel_x>=11'd453 && pixel_x<11'd460 && pixel_y>=10'd114 && pixel_y<10'd121));
    wire [6:0] emergency_dx=pixel_x>=11'd384 ? pixel_x[6:0] : 7'd0-pixel_x[6:0];
    wire [6:0] emergency_dy=pixel_y[6:0]-7'd56;
    wire [5:0] emergency_half=emergency_dy[6:1];
    wire emergency_icon=emergency_active && pixel_x>=11'd341 && pixel_x<11'd428 &&
                        pixel_y>=10'd56 && pixel_y<10'd144 && emergency_dx<=emergency_half;
    wire emergency_mark=emergency_active &&
                        ((pixel_x>=11'd380 && pixel_x<11'd389 && pixel_y>=10'd80 && pixel_y<10'd116) ||
                         (pixel_x>=11'd380 && pixel_x<11'd389 && pixel_y>=10'd124 && pixel_y<10'd133));

    function [71:0] warning_text_row;
        input [3:0] row;
        begin
            case(row)
                2:warning_text_row=72'h0010fcc63cc67c0000;
                3:warning_text_row=72'hc63866e618e6c60000;
                4:warning_text_row=72'hc66c66f618f6c60000;
                5:warning_text_row=72'hc6c666fe18fec00000;
                6:warning_text_row=72'hc6c67cde18dec00000;
                7:warning_text_row=72'hc6fe6cce18cece0000;
                8,9:warning_text_row=72'hc6c666c618c6c60000;
                10:warning_text_row=72'hd6c666c618c6c60000;
                11:warning_text_row=72'hd6c6e6c63cc67c0000;
                12:warning_text_row=72'hee0000000000000000;
                13:warning_text_row=72'h6c0000000000000000;
                default:warning_text_row=0;
            endcase
        end
    endfunction

    function [71:0] emergency_text_row;
        input [3:0] row;
        begin
            case(row)
                2:emergency_text_row=72'hfec6fefc7cfec67c66;
                3:emergency_text_row=72'h66ee6666c666e6c666;
                4:emergency_text_row=72'h62fe6266c662f6c266;
                5:emergency_text_row=72'h68fe6866c068fec066;
                6:emergency_text_row=72'h78d6787cc078dec03c;
                7:emergency_text_row=72'h68c6686cce68cec018;
                8:emergency_text_row=72'h60c66066c660c6c018;
                9:emergency_text_row=72'h62c66266c662c6c018;
                10:emergency_text_row=72'h66c66666c666c6c018;
                11:emergency_text_row=72'hfec6fee67cfec6c23c;
                12:emergency_text_row=72'h00000000000000c600;
                13:emergency_text_row=72'h000000000000007c00;
                default:emergency_text_row=0;
            endcase
        end
    endfunction

    function [6:0] alert_glyph;
        input [1:0] line_id;
        input [3:0] position;
        begin
            alert_glyph=BLANK_GLYPH;
            case(line_id)
                0:case(position)
                    0:alert_glyph=35;1:alert_glyph=45;2:alert_glyph=38;3:alert_glyph=66;
                    4:alert_glyph=74;5:alert_glyph=27;6:alert_glyph=21;7:alert_glyph=60;
                    8:alert_glyph=52;9:alert_glyph=63;10:alert_glyph=42;11:alert_glyph=1;
                    12:alert_glyph=0;13:alert_glyph=12;14:alert_glyph=68;
                endcase
                1:case(position)
                    0:alert_glyph=67;1:alert_glyph=59;2:alert_glyph=35;3:alert_glyph=45;
                    4:alert_glyph=38;5:alert_glyph=66;6:alert_glyph=73;7:alert_glyph=61;
                    8:alert_glyph=16;9:alert_glyph=41;10:alert_glyph=54;11:alert_glyph=51;
                    12:alert_glyph=14;13:alert_glyph=35;14:alert_glyph=5;15:alert_glyph=19;
                endcase
            endcase
        end
    endfunction

    reg legacy_text_valid,text_valid;
    reg [1:0] text_line;
    reg [3:0] legacy_text_row,text_row,text_col,text_position;
    reg [6:0] legacy_text_col;
    always @(*) begin
        legacy_text_valid=1'b0;legacy_text_row=0;legacy_text_col=0;
        if(warning_active && pixel_x>=11'd520 && pixel_x<11'd664 &&
           pixel_y>=10'd80 && pixel_y<10'd112) begin
            legacy_text_valid=1'b1;legacy_text_row=(pixel_y-10'd80)>>1;
            legacy_text_col=(pixel_x-11'd520)>>1;
        end else if(emergency_active && pixel_x>=11'd464 && pixel_x<11'd608 &&
                    pixel_y>=10'd88 && pixel_y<10'd120) begin
            legacy_text_valid=1'b1;legacy_text_row=(pixel_y-10'd88)>>1;
            legacy_text_col=(pixel_x-11'd464)>>1;
        end
    end
    always @(*) begin
        text_valid=1'b0;text_line=0;text_row=0;text_col=0;text_position=0;
        if(warning_active && pixel_x>=11'd520 && pixel_x<11'd760 &&
           pixel_y>=10'd120 && pixel_y<10'd136) begin
            text_valid=1'b1;text_line=0;text_row=pixel_y-10'd120;
            text_position=(pixel_x-11'd520)>>4;text_col=pixel_x-11'd520;
        end else if(emergency_active && pixel_x>=11'd512 && pixel_x<11'd768 &&
                    pixel_y>=10'd136 && pixel_y<10'd152) begin
            text_valid=1'b1;text_line=1;text_row=pixel_y-10'd136;
            text_position=(pixel_x-11'd512)>>4;text_col=pixel_x-11'd512;
        end
    end
    assign u6_glyph_id=text_valid ? alert_glyph(text_line,text_position) : BLANK_GLYPH;
    assign u6_glyph_row=text_row;

    reg s_valid,s_user,s_last,s_emergency;
    reg [14:0] s_x,s_y;
    reg [23:0] s_rgb;
    reg s_border,s_banner,s_icon,s_mark,s_legacy_text_valid,s_text_valid;
    reg s_legacy_emergency;
    reg [3:0] s_legacy_text_row,s_text_col;
    reg [6:0] s_legacy_text_col;
    wire [71:0] legacy_text_bits=s_legacy_emergency ?
        emergency_text_row(s_legacy_text_row) : warning_text_row(s_legacy_text_row);
    wire legacy_text_on=s_legacy_text_valid &&
                        legacy_text_bits[7'd71-s_legacy_text_col];
    wire text_on=s_text_valid && u6_glyph_bits[4'd15-s_text_col];

    reg [23:0] attention_rgb;
    always @(*) begin
        attention_rgb=s_rgb;
        if(s_banner)
            attention_rgb=s_emergency ? EMERGENCY_BANNER : WARNING_BANNER;
        if(s_border)
            attention_rgb=s_emergency ? EMERGENCY_BORDER : WARNING_BORDER;
        if(s_icon)
            attention_rgb=s_emergency ? EMERGENCY_TEXT : WARNING_BORDER;
        if(s_mark)
            attention_rgb=s_emergency ? EMERGENCY_BANNER : WARNING_MARK;
        if(legacy_text_on)
            attention_rgb=s_legacy_emergency ? EMERGENCY_TEXT : WARNING_TEXT;
        if(text_on)
            attention_rgb=s_emergency ? EMERGENCY_TEXT : WARNING_TEXT;
    end

    always @(posedge clk or posedge rst) begin
        if(rst) begin
            event_active_q<=0;event_level_q<=0;event_id_q<=0;event_epoch_q<=0;
            s_valid<=0;s_user<=0;s_last<=0;s_x<=0;s_y<=0;s_rgb<=0;
            s_emergency<=0;s_border<=0;s_banner<=0;s_icon<=0;s_mark<=0;
            s_legacy_emergency<=0;s_legacy_text_valid<=0;s_legacy_text_row<=0;
            s_legacy_text_col<=0;s_text_valid<=0;s_text_col<=0;
            out_valid<=0;out_user<=0;out_last<=0;out_x<=0;out_y<=0;out_rgb<=0;
        end else begin
            if(first) begin
                event_active_q<=event_active_pending;event_level_q<=event_level_pending;
                event_id_q<=event_id_pending;event_epoch_q<=event_epoch_pending;
            end
            s_valid<=in_valid;s_user<=in_user;s_last<=in_last;s_x<=in_x;s_y<=in_y;
            s_rgb<=base_rgb;s_emergency<=emergency_active;
            s_border<=border_on;s_banner<=banner_on;
            s_icon<=warning_icon || emergency_icon;
            s_mark<=warning_mark || emergency_mark;
            s_legacy_emergency<=emergency_active;s_legacy_text_valid<=legacy_text_valid;
            s_legacy_text_row<=legacy_text_row;s_legacy_text_col<=legacy_text_col;
            s_text_valid<=text_valid;s_text_col<=text_col;
            out_valid<=s_valid;out_user<=s_user;out_last<=s_last;
            out_x<=s_x;out_y<=s_y;out_rgb<=attention_rgb;
        end
    end
endmodule
