// Shared normal Chinese Product display, with three complete packet stages.
module m9_product_ui_renderer #(parameter integer ENABLE_VOLUME_OSD=0) (
    input wire clk,input wire rst,
    input wire in_valid,input wire in_user,input wire in_last,
    input wire [14:0] in_x,input wire [14:0] in_y,input wire [23:0] in_rgb,
    input wire [1:0] theme_pending,
    input wire brightness_visible_pending,input wire [3:0] display_level_pending,
    input wire ready_pending,input wire error_pending,
    input wire volume_visible_pending,input wire [3:0] volume_level_pending,
    output wire out_valid,output wire out_user,output wire out_last,
    output wire [14:0] out_x,output wire [14:0] out_y,output wire [23:0] out_rgb,
    output wire out_subtitle_first
);
    localparam [23:0] HEADER_BG=24'hedf5fc,PANEL_BG=24'hf7fafe;
    localparam [23:0] TEXT=24'h16436a,TITLE=24'h145da0,GOOD=24'h137a55;
    localparam [23:0] WARNING=24'h946400,FAULT=24'hc32942,MUTED=24'h657d91;
    reg brightness_q,ready_q,error_q;
    reg [1:0] theme_q;
    reg [3:0] level_q;
    wire first=in_valid && in_user;
    wire brightness=first ? brightness_visible_pending : brightness_q;
    wire in_canvas=in_x<15'd1280 && in_y<15'd720;
    wire header=in_x>=15'd24 && in_x<15'd1256 && in_y>=15'd16 && in_y<15'd80;
    wire care=in_x>=15'd24 && in_x<15'd248 && in_y>=15'd184 && in_y<15'd424;
    wire reserved=in_x>=15'd1032 && in_x<15'd1256 && in_y>=15'd184 && in_y<15'd424;
    wire brightness_box=brightness && in_x>=15'd1032 && in_x<15'd1256 &&
                        in_y>=15'd464 && in_y<15'd512;
    wire volume_box;
    wire [23:0] volume_rgb;
    generate if(ENABLE_VOLUME_OSD) begin: g_volume
        reg visible_q;
        reg [3:0] volume_q;
        wire volume_visible=first ? volume_visible_pending : visible_q;
        wire [3:0] volume_level=first ? volume_level_pending : volume_q;
        always @(posedge clk or posedge rst) begin
            if(rst) begin visible_q<=0;volume_q<=4;end
            else if(first) begin visible_q<=volume_visible_pending;volume_q<=volume_level_pending;end
        end
        assign volume_box=volume_visible && in_x>=1032 && in_x<1256 && in_y>=464 && in_y<512;
        m9_volume_osd_pixels u_pixels(.x(in_x),.y(in_y),.level(volume_level),.rgb(volume_rgb));
    end else begin: g_no_volume
        assign volume_box=1'b0;
        assign volume_rgb=PANEL_BG;
    end endgenerate
    wire panel=care || reserved || brightness_box || volume_box;
    wire opaque=in_valid && in_canvas && (header || panel);
    wire [14:0] grid_x=in_x-15'd8;
    wire [3:0] line_index;
    wire [12:0] descriptor;
    m9_ui_line_index u_line(.physical_row(in_y[9:5]),.line_index(line_index));
    m9_ui_text_rom u_text(.clk(clk),.diagnostic(1'b0),.line_index(line_index),
        .column_index(grid_x[10:4]),.descriptor(descriptor));

    reg [56:0] s_packet,m_packet,t_packet;
    reg s_text,s_header;
    reg [3:0] s_column;
    reg [4:0] s_row;
    reg m_text,t_text;
    reg [4:0] m_column,t_column,m_row;
    reg [7:0] m_glyph;
    reg [2:0] m_color_role;
    reg [23:0] t_color;
    wire [7:0] token=descriptor[7:0];
    wire [3:0] color_class=descriptor[12:9];
    reg [2:0] product_status;
    always @(*) begin
        product_status=0;
        if(error_q) product_status=3;
        else if(ready_q) product_status=1;
    end
    wire [7:0] product_glyph;
    reg [7:0] theme_glyph,level_glyph;
    // Exact cases preserve replacement glyphs for reserved and X/Z numeric inputs.
    always @(*) begin
        case(theme_q)
            0:theme_glyph=4;1:theme_glyph=5;2:theme_glyph=6;3:theme_glyph=7;
            default:theme_glyph=1;
        endcase
        case(level_q)
            0:level_glyph=3;1:level_glyph=4;2:level_glyph=5;3:level_glyph=6;
            4:level_glyph=7;5:level_glyph=8;6:level_glyph=9;7:level_glyph=10;
            8:level_glyph=11;9:level_glyph=12;default:level_glyph=1;
        endcase
    end
    m9_ui_status_map u_product_status(.status(product_status),.position(token[2:0]),
        .glyph_id(product_glyph));
    wire status_token=token>=8'd192 && token<8'd198;
    wire theme_token=token==8'd184,level_token=token==8'd185;
    wire static_token=!(status_token || theme_token || level_token);
    wire [7:0] glyph_id=({8{status_token}} & product_glyph) |
        ({8{theme_token}} & theme_glyph) | ({8{level_token}} & level_glyph) |
        ({8{static_token}} & token);
    wire half=descriptor[8];
    wire [23:0] glyph_bits;
    m9_ui_glyph_rom u_glyph(.clk(clk),.glyph_id(m_glyph),.row(m_row),.bits(glyph_bits));
    reg [2:0] color_role;
    reg [23:0] color_rgb;
    function [23:0] palette_color;
        input [2:0] role;
        begin
            case(role)
                1:palette_color=TITLE;
                2:palette_color=GOOD;
                3:palette_color=WARNING;
                4:palette_color=FAULT;
                5:palette_color=MUTED;
                default:palette_color=TEXT;
            endcase
        end
    endfunction
    always @(*) begin
        case(color_class)
            1:color_role=1;
            10:color_role=5;
            default:color_role=0;
        endcase
        if(status_token && s_header) begin
            case(product_status)
                1:color_role=2;
                2:color_role=3;
                3:color_role=4;
                default:color_role=5;
            endcase
        end
        color_rgb=palette_color(color_role);
    end
    assign out_valid=t_packet[56];assign out_user=t_packet[55];assign out_last=t_packet[54];
    assign out_x=t_packet[53:39];assign out_y=t_packet[38:24];
    assign out_rgb=t_text && t_column<24 && glyph_bits[23-t_column] ?
                   t_color : t_packet[23:0];
    // Middle-stage SOF lets Subtitle preserve the frozen-D1 pending-sample edge.
    assign out_subtitle_first=m_packet[56] && m_packet[55];
    always @(posedge clk or posedge rst) begin
        if(rst) begin
            brightness_q<=0;ready_q<=0;error_q<=0;
            theme_q<=0;level_q<=1;
            s_packet<=0;m_packet<=0;t_packet<=0;
            s_text<=0;s_header<=0;s_column<=0;s_row<=0;
            m_text<=0;m_column<=0;m_row<=0;m_glyph<=0;m_color_role<=0;
            t_text<=0;t_column<=0;t_color<=0;
        end else begin
            if(first) begin
                brightness_q<=brightness_visible_pending;
                ready_q<=ready_pending;error_q<=error_pending;theme_q<=theme_pending;
                level_q<=display_level_pending;
            end
            s_packet<={in_valid,in_user,in_last,in_x,in_y,
                       (opaque ? (header ? HEADER_BG : (volume_box ? volume_rgb : PANEL_BG)) : in_rgb)};
            s_text<=opaque && !volume_box && in_x>=8 && in_y[4:0]<24 && line_index!=0;
            s_header<=header;s_column<=grid_x[3:0];s_row<=in_y[4:0];
            m_packet<=s_packet;m_text<=s_text;
            m_column<={half,s_column};m_row<=s_row;m_glyph<=glyph_id;m_color_role<=color_role;
            t_packet<=m_packet;t_text<=m_text;
            t_column<=m_column;t_color<=palette_color(m_color_role);
        end
    end
endmodule

// Procedural icon/digit/bar reuse the existing packet RGB, without another
// ROM, pixel stage, multiplier or divider. Mute shows digit 0 and an empty bar.
module m9_volume_osd_pixels (
    input wire [14:0] x,input wire [14:0] y,input wire [3:0] level,
    output wire [23:0] rgb
);
    localparam [23:0] BACKGROUND=24'hf7fafe,INK=24'h087f9b,EMPTY=24'hc9dce7;
    reg [6:0] segments;
    always @(*) begin
        case(level)
            0:segments=7'b1111110;1:segments=7'b0110000;2:segments=7'b1101101;
            3:segments=7'b1111001;4:segments=7'b0110011;5:segments=7'b1011011;
            6:segments=7'b1011111;7:segments=7'b1110000;8:segments=7'b1111111;
            default:segments=0;
        endcase
    end
    wire speaker=(x>=1048 && x<1056 && y>=480 && y<492) ||
                 (x>=1056 && x<1062 && y>=476 && y<496) ||
                 (x>=1066 && x<1069 && y>=480 && y<492);
    wire horizontal=x>=1082 && x<1094;
    wire left_side=x>=1080 && x<1083,right_side=x>=1093 && x<1096;
    wire upper=y>=478 && y<487,lower=y>=489 && y<498;
    wire digit=(segments[6] && horizontal && y>=476 && y<479) ||
               (segments[5] && right_side && upper) ||
               (segments[4] && right_side && lower) ||
               (segments[3] && horizontal && y>=497 && y<500) ||
               (segments[2] && left_side && lower) ||
               (segments[1] && left_side && upper) ||
               (segments[0] && horizontal && y>=486 && y<490);
    wire bar=x>=1104 && x<1248 && y>=480 && y<496 && x[3:0]>=2 && x[3:0]<14;
    wire filled=level<=8 && level!=0 && x[7:4]<=({1'b0,level}+5'd5);
    assign rgb=(speaker || digit) ? INK : bar ? (filled ? INK : EMPTY) : BACKGROUND;
endmodule
