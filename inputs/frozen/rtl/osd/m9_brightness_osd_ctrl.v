`timescale 1ns/1ps

// Frame-counted display only; the existing nine-level brightness ring is external.
// SOF outputs are the pre-edge values sampled by the first pixel consumer.
module m9_brightness_osd_ctrl #(
    parameter integer VISIBLE_FRAMES=182
)(
    input wire clk,
    input wire rst,
    input wire frame_first,
    input wire event_pending,
    input wire [3:0] level_pending,
    output wire visible,
    output wire [3:0] display_level
);
    localparam [7:0] FRAME_RELOAD=VISIBLE_FRAMES;
    reg [7:0] remaining;
    reg pending_event;
    reg [3:0] level_q;

    initial begin
        if(VISIBLE_FRAMES<1 || VISIBLE_FRAMES>255)
            $fatal(1,"M9_BRIGHTNESS_CONFIG_ERROR VISIBLE_FRAMES must be 1..255");
    end

    assign visible=!rst && (frame_first ?
                   (pending_event || remaining>8'd1) : remaining!=8'd0);
    assign display_level=frame_first ? level_pending+4'd1 : level_q;

    always @(posedge clk or posedge rst) begin
        if(rst) begin
            remaining<=8'd0;
            pending_event<=1'b0;
            level_q<=4'd1;
        end else begin
            if(frame_first) begin
                // Consume only the previously latched event. A same-edge event
                // remains pending so the external ring can advance first.
                pending_event<=event_pending;
                level_q<=level_pending+4'd1;
                if(pending_event)
                    remaining<=FRAME_RELOAD;
                else if(remaining!=8'd0)
                    remaining<=remaining-8'd1;
            end else if(event_pending)
                pending_event<=1'b1;
        end
    end
endmodule
