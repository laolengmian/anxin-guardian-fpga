// Request the Health bundle after the final active line so the CDC commit
// completes in vertical blank and remains stable throughout the next frame.
module m9_health_snapshot_trigger #(
    parameter [14:0] LAST_ACTIVE_Y=15'd719
) (
    input wire pixel_valid,input wire pixel_last,input wire [14:0] pixel_y,
    input wire snapshot_busy,output wire request
);
    assign request=pixel_valid && pixel_last &&
                   pixel_y==LAST_ACTIVE_Y && !snapshot_busy;
endmodule
