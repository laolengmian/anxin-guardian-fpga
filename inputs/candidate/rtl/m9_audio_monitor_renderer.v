// M9-private full-range PCM16 envelope; the same 128-point visible history
// has a synchronous read; every pipeline stage delays the complete pixel packet.
module m9_audio_monitor_renderer (
    input wire clk,input wire rst,input wire in_valid,input wire in_user,input wire in_last,
    input wire [14:0] in_x,input wire [14:0] in_y,input wire [23:0] in_rgb,
    input wire monitor_enable,input wire [7:0] write_ptr_pending,
    input wire [8:0] point_count_pending,input wire [15:0] latest_peak_pending,
    input wire [1:0] clip_id_pending,input wire play_active_pending,
    output wire [7:0] envelope_read_addr,input wire [47:0] envelope_read_data,
    output reg out_valid,output reg out_user,output reg out_last,
    output reg [14:0] out_x,output reg [14:0] out_y,output reg [23:0] out_rgb
);
    localparam [23:0] BASELINE_RGB=24'h657d91;
    localparam [23:0] WAVE_RGB=24'h176f9d;
    localparam [23:0] LATEST_RGB=24'h16436a;
    localparam [23:0] PEAK_RGB=24'h946400;
    localparam [23:0] TEXT_RGB=24'h16436a;
    localparam integer PCM_PIXEL_SHIFT=10,PEAK_PIXEL_SHIFT=9;
    reg enable_q;
    reg [7:0] write_ptr_q;
    reg [8:0] point_count_q;
    reg [15:0] latest_peak_q;
    reg [1:0] clip_id_q;
    reg play_active_q;
    wire first=in_valid && in_user;
    wire enable_active=first ? monitor_enable : enable_q;
    wire [7:0] write_ptr_active=first ? write_ptr_pending : write_ptr_q;
    wire [8:0] point_count_active=first ? point_count_pending : point_count_q;
    wire [15:0] latest_peak_active=first ? latest_peak_pending : latest_peak_q;
    wire [1:0] clip_id_active=first ? clip_id_pending : clip_id_q;
    wire play_active=first ? play_active_pending : play_active_q;
    wire [8:0] visible_count=point_count_active>=9'd128 ? 9'd128 : point_count_active;
    wire [7:0] first_column=8'd128-visible_count[7:0];
    wire [14:0] monitor_x=in_x-15'd224;
    wire [7:0] monitor_column={1'b0,monitor_x[9:3]};
    wire column_has_point=in_x>=224 && in_x<1248 && visible_count!=0 &&
                          monitor_column>=first_column;
    wire [7:0] oldest_address=write_ptr_active-visible_count[7:0];
    assign envelope_read_addr=column_has_point ?
        oldest_address+(monitor_column-first_column) : 8'd0;

    reg s_valid,s_user,s_last,s_enable,s_wave_valid;
    reg [14:0] s_x,s_y;
    reg [23:0] s_rgb;
    reg [7:0] s_column;
    reg [15:0] s_peak;
    reg [1:0] s_clip;
    reg s_play_active;

    reg t_valid,t_user,t_last;
    reg [14:0] t_x,t_y;
    reg [23:0] t_rgb;
    reg t_baseline_on,t_peak_on,t_wave_on,t_wave_latest,t_text_valid;
    reg [127:0] t_glyph;
    reg t_is_w;
    reg [3:0] t_text_row;
    reg [23:0] t_text_color;

    reg m_valid,m_user,m_last;
    reg [14:0] m_x,m_y;
    reg [23:0] m_rgb;
    reg m_baseline_on,m_peak_on,m_wave_on,m_wave_latest,m_text_on;
    reg [23:0] m_text_color;

    reg signed [15:0] point_min,point_max;
    reg signed [8:0] min_scale,max_scale;
    reg signed [15:0] wave_top_calc,wave_bottom_calc;
    reg [14:0] wave_top,wave_bottom;
    reg [7:0] peak_height;
    reg [23:0] monitor_rgb;
    reg text_line_valid;
    reg [79:0] text_line;
    reg [3:0] text_row;
    reg [23:0] text_color;
    wire [14:0] text_gx=s_x-15'd40;
    wire [10:0] text_column=text_gx[14:3];
    wire [7:0] text_char=text_column<10 ? text_line[(9-text_column)*8+:8] : 8'h20;
    always @(*) begin
        text_line_valid=0;text_line="          ";text_row=0;text_color=TEXT_RGB;
        if(s_y>=624 && s_y<640) begin
            text_line_valid=1;text_line="AUDIO DATA";text_row=s_y-624;
        end else if(s_y>=648 && s_y<664) begin
            text_line_valid=1;text_line="MONO OUT  ";text_row=s_y-648;
        end
    end

    // Same complete table as font_rom_ascii; decode before the existing T edge.
    function [127:0] decode_glyph;
        input [7:0] char_code;
        begin
            case(char_code)
                8'h20: decode_glyph = 128'h00000000000000000000000000000000;
                8'h41: decode_glyph = 128'h000010386CC6C6FEC6C6C6C600000000;
                8'h42: decode_glyph = 128'h0000FC6666667C66666666FC00000000;
                8'h44: decode_glyph = 128'h0000F86C6666666666666CF800000000;
                8'h45: decode_glyph = 128'h0000FE6662687868606266FE00000000;
                8'h46: decode_glyph = 128'h0000FE6662687868606060F000000000;
                8'h47: decode_glyph = 128'h00007CC6C6C0C0CEC6C6C67C00000000;
                8'h48: decode_glyph = 128'h0000C6C6C6C6FEC6C6C6C6C600000000;
                8'h49: decode_glyph = 128'h00003C18181818181818183C00000000;
                8'h4C: decode_glyph = 128'h0000F06060606060606266FE00000000;
                8'h4D: decode_glyph = 128'h0000C6EEFEFED6C6C6C6C6C600000000;
                8'h4E: decode_glyph = 128'h0000C6E6F6FEDECEC6C6C6C600000000;
                8'h4F: decode_glyph = 128'h00007CC6C6C6C6C6C6C6C67C00000000;
                8'h50: decode_glyph = 128'h0000FC6666667C60606060F000000000;
                8'h52: decode_glyph = 128'h0000FC6666667C6C666666E600000000;
                8'h53: decode_glyph = 128'h00007CC6C660380C06C6C67C00000000;
                8'h54: decode_glyph = 128'h00007E5A181818181818183C00000000;
                8'h55: decode_glyph = 128'h0000C6C6C6C6C6C6C6C6C67C00000000;
                8'h58: decode_glyph = 128'h0000C6C66C3838386CC6C6C600000000;
                8'h59: decode_glyph = 128'h0000666666663C181818183C00000000;
                default: decode_glyph = 128'h00007CC6060C18180018180000000000;
            endcase
        end
    endfunction

    reg [7:0] font_bits;
    reg [7:0] w_bits;
    always @(*) begin
        case(t_text_row)
            3,4,5,6,7,8,9:w_bits=8'hc6;
            10,11:w_bits=8'hd6;12:w_bits=8'hee;13:w_bits=8'h6c;
            default:w_bits=0;
        endcase
    end
    always @(*) begin
        case(t_text_row)
            4'd0: font_bits=t_glyph[127:120];
            4'd1: font_bits=t_glyph[119:112];
            4'd2: font_bits=t_glyph[111:104];
            4'd3: font_bits=t_glyph[103:96];
            4'd4: font_bits=t_glyph[95:88];
            4'd5: font_bits=t_glyph[87:80];
            4'd6: font_bits=t_glyph[79:72];
            4'd7: font_bits=t_glyph[71:64];
            4'd8: font_bits=t_glyph[63:56];
            4'd9: font_bits=t_glyph[55:48];
            4'd10: font_bits=t_glyph[47:40];
            4'd11: font_bits=t_glyph[39:32];
            4'd12: font_bits=t_glyph[31:24];
            4'd13: font_bits=t_glyph[23:16];
            4'd14: font_bits=t_glyph[15:8];
            4'd15: font_bits=t_glyph[7:0];
            default: font_bits=8'h00;
        endcase
    end
    wire [7:0] text_bits=t_is_w ? w_bits : font_bits;
    wire text_on=t_text_valid && text_bits[3'd7-t_x[2:0]];

    always @(*) begin
        point_min=$signed(envelope_read_data[47:32]);
        point_max=$signed(envelope_read_data[31:16]);
        min_scale=point_min>>>PCM_PIXEL_SHIFT;max_scale=point_max>>>PCM_PIXEL_SHIFT;
        wave_top_calc=16'sd656-$signed(max_scale);
        wave_bottom_calc=16'sd656-$signed(min_scale);
        wave_top=wave_top_calc[14:0];wave_bottom=wave_bottom_calc[14:0];
        peak_height=(s_peak>>PEAK_PIXEL_SHIFT)>63 ? 8'd63 : {2'd0,s_peak[14:9]};
        monitor_rgb=m_rgb;
        if(m_valid) begin
            if(m_baseline_on) monitor_rgb=BASELINE_RGB;
            if(m_peak_on) monitor_rgb=PEAK_RGB;
            if(m_wave_on) monitor_rgb=m_wave_latest ? LATEST_RGB : WAVE_RGB;
            if(m_text_on) monitor_rgb=m_text_color;
        end
    end

    always @(posedge clk or posedge rst) begin
        if(rst) begin
            enable_q<=0;write_ptr_q<=0;point_count_q<=0;latest_peak_q<=0;
            clip_id_q<=0;play_active_q<=0;
            s_valid<=0;s_user<=0;s_last<=0;s_enable<=0;s_wave_valid<=0;
            s_x<=0;s_y<=0;s_rgb<=0;s_column<=0;s_peak<=0;s_clip<=0;s_play_active<=0;
            t_valid<=0;t_user<=0;t_last<=0;t_x<=0;t_y<=0;t_rgb<=0;
            t_baseline_on<=0;t_peak_on<=0;t_wave_on<=0;t_wave_latest<=0;
            t_text_valid<=0;t_glyph<=decode_glyph(8'h00);t_is_w<=0;
            t_text_row<=0;t_text_color<=0;
            m_valid<=0;m_user<=0;m_last<=0;m_x<=0;m_y<=0;m_rgb<=0;
            m_baseline_on<=0;m_peak_on<=0;m_wave_on<=0;m_wave_latest<=0;
            m_text_on<=0;m_text_color<=0;
            out_valid<=0;out_user<=0;out_last<=0;out_x<=0;out_y<=0;out_rgb<=0;
        end else begin
            if(first) begin
                enable_q<=monitor_enable;write_ptr_q<=write_ptr_pending;
                point_count_q<=point_count_pending;latest_peak_q<=latest_peak_pending;
                clip_id_q<=clip_id_pending;play_active_q<=play_active_pending;
            end
            s_valid<=in_valid;s_user<=in_user;s_last<=in_last;
            s_x<=in_x;s_y<=in_y;
            s_rgb<=in_valid && in_x>=24 && in_x<1256 && in_y>=616 && in_y<696 ?
                   24'hf7fafe : in_rgb;
            s_enable<=enable_active;
            s_wave_valid<=column_has_point;s_column<=monitor_column;
            s_peak<=latest_peak_active;s_clip<=clip_id_active;
            s_play_active<=play_active;

            t_valid<=s_valid;t_user<=s_user;t_last<=s_last;
            t_x<=s_x;t_y<=s_y;t_rgb<=s_rgb;
            t_baseline_on<=s_valid && s_enable && s_x>=224 && s_x<1248 && s_y==656;
            t_peak_on<=s_valid && s_enable && s_x>=1248 && s_x<1252 &&
                       s_y>=688-peak_height && s_y<688;
            t_wave_on<=s_valid && s_enable && s_wave_valid &&
                       (point_min!=0 || point_max!=0) && s_y>=wave_top && s_y<=wave_bottom &&
                       (s_y==wave_top || s_y==wave_bottom || s_x[2:0]==3'd4);
            t_wave_latest<=s_column==8'd127;
            t_text_valid<=s_valid && s_enable && text_line_valid &&
                          s_x>=40 && s_x<120;
            t_glyph<=decode_glyph(text_char);t_is_w<=text_char==8'h57;
            t_text_row<=text_row;t_text_color<=text_color;

            m_valid<=t_valid;m_user<=t_user;m_last<=t_last;
            m_x<=t_x;m_y<=t_y;m_rgb<=t_rgb;
            m_baseline_on<=t_baseline_on;m_peak_on<=t_peak_on;
            m_wave_on<=t_wave_on;m_wave_latest<=t_wave_latest;
            m_text_on<=t_valid && text_on;m_text_color<=t_text_color;

            out_valid<=m_valid;out_user<=m_user;out_last<=m_last;
            out_x<=m_x;out_y<=m_y;out_rgb<=monitor_rgb;
        end
    end
endmodule
