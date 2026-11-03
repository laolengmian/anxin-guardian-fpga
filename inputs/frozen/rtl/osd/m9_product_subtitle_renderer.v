// M9-private subtitle layer for formal Product text and legacy Diagnostic text.
// The complete AXIS/coordinate/RGB bundle retains the frozen two-clock stage.
module m9_product_subtitle_renderer #(
    // Production hides the legacy TONE ONE..FOUR cue overlay; the engineering
    // test variant sets this to 1 to keep the diagnostic captions visible.
    parameter DIAGNOSTIC_CUE_OVERLAY_ENABLE=1'b0
) (
    input wire clk,input wire rst,input wire in_valid,input wire in_user,input wire in_last,
    input wire [14:0] in_x,input wire [14:0] in_y,input wire [23:0] in_rgb,
    input wire diagnostic_pending,input wire clear_pending,input wire active_pending,input wire cue_valid_pending,
    input wire [7:0] cue_index_pending,input wire [7:0] text_id_pending,input wire [1:0] style_pending,
    input wire [3:0] progress_pending,input wire in_pending_first,
    output wire [6:0] u6_glyph_id,output wire [3:0] u6_glyph_row,
    input wire [15:0] u6_glyph_bits,
    output reg out_valid,output reg out_user,output reg out_last,
    output reg [14:0] out_x,output reg [14:0] out_y,output reg [23:0] out_rgb
);
    localparam [23:0] TEXT_WARM=24'h16436a,TEXT_ALERT=24'h946400;
    localparam [6:0] BLANK_GLYPH=7'd127;
    reg active_q,valid_q,diagnostic_q;
    reg [7:0] cue_q,text_q;
    reg [1:0] style_q;
    reg active_d,valid_d,diagnostic_d;
    reg [7:0] cue_d,text_d;
    reg [1:0] style_d;
    wire first=in_valid && in_user;
    wire active=first ? active_d : active_q;
    wire valid=first ? valid_d : valid_q;
    wire [7:0] cue_index=first ? cue_d : cue_q;
    wire [7:0] text_id=first ? text_d : text_q;
    wire [1:0] style=first ? style_d : style_q;
    wire diagnostic=first ? diagnostic_d : diagnostic_q;
    wire [7:0] diagnostic_text_id=cue_index<8'd4 ? cue_index+1'b1 : 8'd0;

    function [7:0] diagnostic_char;
        input [7:0] id;
        input [10:0] position;
        begin
            diagnostic_char=8'h20;
            case(id)
                1,2,3,4:case(position)
                    0:diagnostic_char="T";1:diagnostic_char="O";
                    2:diagnostic_char="N";3:diagnostic_char="E";
                    5:case(id)
                        1:diagnostic_char="O";2,3:diagnostic_char="T";4:diagnostic_char="F";
                    endcase
                    6:case(id)
                        1:diagnostic_char="N";2:diagnostic_char="W";
                        3:diagnostic_char="H";4:diagnostic_char="O";
                    endcase
                    7:case(id)
                        1:diagnostic_char="E";2:diagnostic_char="O";
                        3:diagnostic_char="R";4:diagnostic_char="U";
                    endcase
                    8:case(id)
                        3:diagnostic_char="E";4:diagnostic_char="R";
                    endcase
                    9:if(id==3)diagnostic_char="E";
                    default:diagnostic_char=8'h20;
                endcase
                default:diagnostic_char=8'h20;
            endcase
        end
    endfunction

    function [4:0] product_length;
        input [7:0] id;
        begin
            case(id)
                1,7,8:product_length=7;
                2,5:product_length=4;
                3,6,9,12:product_length=6;
                4,10:product_length=5;
                11:product_length=12;
                default:product_length=0;
            endcase
        end
    endfunction

    function [14:0] product_start_x;
        input [7:0] id;
        begin
            case(id)
                1,7,8:product_start_x=15'd528;
                2,5:product_start_x=15'd576;
                3,6,9,12:product_start_x=15'd544;
                4,10:product_start_x=15'd560;
                11:product_start_x=15'd448;
                default:product_start_x=15'd640;
            endcase
        end
    endfunction

    function [6:0] product_glyph;
        input [7:0] id;
        input [4:0] position;
        begin
            product_glyph=BLANK_GLYPH;
            case(id)
                1:case(position) 0:product_glyph=61;1:product_glyph=7;2:product_glyph=47;3:product_glyph=7;4:product_glyph=55;5:product_glyph=72;6:product_glyph=70;endcase
                2:case(position) 0:product_glyph=25;1:product_glyph=70;2:product_glyph=22;3:product_glyph=71;endcase
                3:case(position) 0:product_glyph=43;1:product_glyph=33;2:product_glyph=57;3:product_glyph=11;4:product_glyph=20;5:product_glyph=58;endcase
                4:case(position) 0:product_glyph=61;1:product_glyph=24;2:product_glyph=28;3:product_glyph=6;4:product_glyph=11;endcase
                5:case(position) 0:product_glyph=26;1:product_glyph=50;2:product_glyph=31;3:product_glyph=53;endcase
                6:case(position) 0:product_glyph=9;1:product_glyph=36;2:product_glyph=32;3:product_glyph=29;4:product_glyph=28;5:product_glyph=31;endcase
                7:case(position) 0:product_glyph=61;1:product_glyph=43;2:product_glyph=33;3:product_glyph=4;4:product_glyph=5;5:product_glyph=15;6:product_glyph=46;endcase
                8:case(position) 0:product_glyph=13;1:product_glyph=44;2:product_glyph=34;3:product_glyph=2;4:product_glyph=22;5:product_glyph=65;6:product_glyph=69;endcase
                9:case(position) 0:product_glyph=49;1:product_glyph=30;2:product_glyph=40;3:product_glyph=39;4:product_glyph=27;5:product_glyph=21;endcase
                10:case(position) 0:product_glyph=61;1:product_glyph=37;2:product_glyph=41;3:product_glyph=17;4:product_glyph=56;endcase
                11:case(position) 0:product_glyph=23;1:product_glyph=42;2:product_glyph=3;3:product_glyph=64;4:product_glyph=16;5:product_glyph=41;6:product_glyph=18;7:product_glyph=48;8:product_glyph=14;9:product_glyph=35;10:product_glyph=5;11:product_glyph=19;endcase
                12:case(position) 0:product_glyph=49;1:product_glyph=30;2:product_glyph=62;3:product_glyph=8;4:product_glyph=10;5:product_glyph=27;endcase
            endcase
        end
    endfunction

    wire [14:0] gx=in_x-15'd560,gy=in_y-15'd556;
    wire [14:0] sx=in_x-15'd562,sy=in_y-15'd558;
    wire [10:0] column=gx[14:4],shadow_column=sx[14:4];
    wire [7:0] char_code=diagnostic_char(diagnostic_text_id,column);
    wire [7:0] shadow_char=diagnostic_char(diagnostic_text_id,shadow_column);
    wire band_window=in_x>=24 && in_x<1256 && in_y>=544 && in_y<600;
    wire main_window=in_x>=560 && in_x<720 && in_y>=556 && in_y<588;
    wire shadow_window=in_x>=562 && in_x<722 && in_y>=558 && in_y<590;

    wire [14:0] product_x0=product_start_x(text_id);
    wire [4:0] product_chars=product_length(text_id);
    wire [14:0] product_width={product_chars,5'b0};
    wire [14:0] product_gx=in_x-product_x0;
    wire product_window=!diagnostic && product_chars!=0 &&
                        in_x>=product_x0 && in_x<product_x0+product_width &&
                        in_y>=15'd556 && in_y<15'd588;
    wire [4:0] product_position=product_gx[9:5];
    assign u6_glyph_id=product_window ? product_glyph(text_id,product_position) : BLANK_GLYPH;
    assign u6_glyph_row=gy[4:1];

    reg [56:0] s_packet;
    reg s_active,s_cue_valid,s_diagnostic,s_band,s_main,s_shadow,s_product;
    reg [1:0] s_style;
    reg [7:0] s_char,s_shadow_char;
    reg [3:0] s_row,s_shadow_row,s_product_pixel;
    reg [2:0] s_pixel,s_shadow_pixel;
    wire [7:0] base_bits,shadow_base_bits;
    reg [7:0] w_bits,shadow_w_bits;
    always @(*) begin
        case(s_row)
            3,4,5,6,7,8,9:w_bits=8'hc6;
            10,11:w_bits=8'hd6;12:w_bits=8'hee;13:w_bits=8'h6c;
            default:w_bits=0;
        endcase
        case(s_shadow_row)
            3,4,5,6,7,8,9:shadow_w_bits=8'hc6;
            10,11:shadow_w_bits=8'hd6;12:shadow_w_bits=8'hee;13:shadow_w_bits=8'h6c;
            default:shadow_w_bits=0;
        endcase
    end
    font_rom_ascii u_font(.char_code(s_char),.row(s_row),.bits(base_bits));
    font_rom_ascii u_shadow_font(.char_code(s_shadow_char),.row(s_shadow_row),.bits(shadow_base_bits));
    wire [7:0] glyph_bits=s_char==8'h57 ? w_bits : base_bits;
    wire [7:0] shadow_bits=s_shadow_char==8'h57 ? shadow_w_bits : shadow_base_bits;
    wire glyph_on=glyph_bits[3'd7-s_pixel];
    wire shadow_on=shadow_bits[3'd7-s_shadow_pixel];
    wire product_on=u6_glyph_bits[4'd15-s_product_pixel];
    reg [23:0] rgb;
    always @(*) begin
        rgb=s_packet[56] && s_band ? 24'hf7fafe : s_packet[23:0];
        if(s_packet[56] && s_active && s_cue_valid) begin
            if(s_diagnostic) begin
                if(DIAGNOSTIC_CUE_OVERLAY_ENABLE) begin
                    if(s_shadow && shadow_on) rgb=24'h000000;
                    if(s_main && glyph_on) rgb=s_style==0 ? TEXT_WARM : TEXT_ALERT;
                end
            end else if(s_product && product_on)
                rgb=s_style==0 ? TEXT_WARM : TEXT_ALERT;
        end
    end

    // progress_pending remains in the stable interface but is deliberately not
    // rendered: the former diagnostic progress bar has no user-facing purpose.
    always @(posedge clk or posedge rst) begin
        if(rst) begin
            active_q<=0;valid_q<=0;cue_q<=0;text_q<=0;style_q<=0;diagnostic_q<=0;
            active_d<=0;valid_d<=0;cue_d<=0;text_d<=0;style_d<=0;diagnostic_d<=0;
            s_packet<=0;s_active<=0;s_cue_valid<=0;s_diagnostic<=0;s_style<=0;
            s_char<=0;s_shadow_char<=0;s_row<=0;s_shadow_row<=0;
            s_pixel<=0;s_shadow_pixel<=0;s_product_pixel<=0;
            s_band<=0;s_main<=0;s_shadow<=0;s_product<=0;
            out_valid<=0;out_user<=0;out_last<=0;out_x<=0;out_y<=0;out_rgb<=0;
        end else begin
            active_d<=active_pending && !clear_pending;
            valid_d<=cue_valid_pending && !clear_pending;
            cue_d<=cue_index_pending;text_d<=text_id_pending;
            style_d<=style_pending;diagnostic_d<=diagnostic_pending;
            if(in_pending_first) begin
                active_q<=active_pending && !clear_pending;
                valid_q<=cue_valid_pending && !clear_pending;
                cue_q<=cue_index_pending;text_q<=text_id_pending;
                style_q<=style_pending;diagnostic_q<=diagnostic_pending;
            end
            s_packet<={in_valid,in_user,in_last,in_x,in_y,in_rgb};
            s_active<=active;s_cue_valid<=valid;s_diagnostic<=diagnostic;s_style<=style;
            s_char<=char_code;s_shadow_char<=shadow_char;
            s_row<=gy[4:1];s_shadow_row<=sy[4:1];
            s_pixel<=gx[3:1];s_shadow_pixel<=sx[3:1];
            s_product_pixel<=product_gx[4:1];
            s_band<=band_window;s_main<=main_window;s_shadow<=shadow_window;
            s_product<=product_window;
            out_valid<=s_packet[56];out_user<=s_packet[55];out_last<=s_packet[54];
            out_x<=s_packet[53:39];out_y<=s_packet[38:24];out_rgb<=rgb;
        end
    end
endmodule
