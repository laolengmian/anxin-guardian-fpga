// M9-private raw-coordinate alignment and shared three-stage UI/media backend.
module m9_product_video_pipeline #(parameter integer ENABLE_VOLUME_OSD=0) (
    input wire clk,input wire rst,
    input wire [11:0] raw_x,input wire [11:0] raw_y,
    input wire in_valid,input wire in_user,input wire in_last,input wire [23:0] in_rgb,
    input wire [1:0] theme_pending,input wire [3:0] level_pending,
    input wire signed [8:0] offset_pending,input wire brightness_event_pending,
    input wire ready_pending,input wire error_pending,
    input wire volume_event_pending,input wire [3:0] volume_level_pending,
    output wire out_valid,output wire out_user,output wire out_last,
    output wire [14:0] out_x,output wire [14:0] out_y,output wire [23:0] out_rgb,
    output wire out_subtitle_first
);
    reg [11:0] packet_x,packet_y;
    reg signed [8:0] offset_q;
    wire first=in_valid && in_user;
    wire signed [8:0] offset_for_pixel=first ? offset_pending : offset_q;
    wire brightness_visible;
    wire [3:0] display_level;
    // Same signed saturating channel arithmetic as the frozen brightness_adjust,
    // moved before the shared packet registers; never affects opaque UI colors.
    function [7:0] sat_add;
        input [7:0] base;input signed [8:0] amount;
        reg signed [9:0] sum;
        begin
            sum=$signed({1'b0,base})+amount;
            if(sum>10'sd255) sat_add=8'd255;
            else if(sum<10'sd0) sat_add=8'd0;
            else sat_add=sum[7:0];
        end
    endfunction
    wire [23:0] adjusted_rgb={sat_add(in_rgb[23:16],offset_for_pixel),
        sat_add(in_rgb[15:8],offset_for_pixel),sat_add(in_rgb[7:0],offset_for_pixel)};
    always @(posedge clk or posedge rst) begin
        if(rst) begin packet_x<=0;packet_y<=0;offset_q<=0;end
        else begin
            packet_x<=raw_x;packet_y<=raw_y;
            if(first) offset_q<=offset_pending;
        end
    end
    m9_brightness_osd_ctrl u_brightness_osd(
        .clk(clk),.rst(rst),.frame_first(first),.event_pending(brightness_event_pending),
        .level_pending(level_pending),.visible(brightness_visible),.display_level(display_level));
    wire volume_visible;
    wire [3:0] volume_display_level;
    generate if(ENABLE_VOLUME_OSD) begin: g_volume_osd
        m9_volume_osd_ctrl u_volume_osd(
            .clk(clk),.rst(rst),.frame_first(first),
            .volume_event(volume_event_pending),.brightness_event(brightness_event_pending),
            .volume_level(volume_level_pending),.visible(volume_visible),
            .display_level(volume_display_level));
    end else begin: g_no_volume_osd
        assign volume_visible=1'b0;
        assign volume_display_level=4'd0;
    end endgenerate
    m9_product_ui_renderer #(.ENABLE_VOLUME_OSD(ENABLE_VOLUME_OSD)) u_ui(
        .clk(clk),.rst(rst),.in_valid(in_valid),.in_user(in_user),.in_last(in_last),
        .in_x({3'd0,packet_x}),.in_y({3'd0,packet_y}),.in_rgb(adjusted_rgb),
        .theme_pending(theme_pending),
        .brightness_visible_pending(brightness_visible),.display_level_pending(display_level),
        .volume_visible_pending(volume_visible),.volume_level_pending(volume_display_level),
        .ready_pending(ready_pending),.error_pending(error_pending),
        .out_valid(out_valid),.out_user(out_user),.out_last(out_last),
        .out_x(out_x),.out_y(out_y),.out_rgb(out_rgb),
        .out_subtitle_first(out_subtitle_first));
endmodule

// Last control event selects the shared box; ties favor volume. Events on SOF
// are deferred one frame so the CDC-delivered level has already settled.
module m9_volume_osd_ctrl #(parameter integer VISIBLE_FRAMES=91) (
    input wire clk,input wire rst,input wire frame_first,
    input wire volume_event,input wire brightness_event,input wire [3:0] volume_level,
    output wire visible,output wire [3:0] display_level
);
    reg [6:0] remaining;
    reg pending_event,pending_volume;
    reg [3:0] level_q;
    wire event_now=volume_event || brightness_event;
    wire next_visible=pending_event ? pending_volume : remaining>1;
    assign visible=!rst && (frame_first ? next_visible : remaining!=0);
    assign display_level=frame_first ? volume_level : level_q;
    always @(posedge clk or posedge rst) begin
        if(rst) begin remaining<=0;pending_event<=0;pending_volume<=0;level_q<=4;end
        else begin
            if(frame_first) begin
                level_q<=volume_level;
                if(pending_event) remaining<=pending_volume ? VISIBLE_FRAMES : 0;
                else if(remaining!=0) remaining<=remaining-1'b1;
                pending_event<=event_now;
            end else if(event_now) pending_event<=1'b1;
            if(event_now) pending_volume<=volume_event;
        end
    end
endmodule
