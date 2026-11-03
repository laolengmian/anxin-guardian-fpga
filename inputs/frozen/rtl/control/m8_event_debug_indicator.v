// M8-A physical audit sink. The active-low seven-segment decimal point lights
// only after video and audio hold the same active event record. One-cycle apply
// pulses also exercise the sink; media-error display retains absolute priority.
module m8_event_debug_indicator (
    input wire video_apply,input wire video_active,
    input wire [1:0] video_level,input wire [7:0] video_event_id,
    input wire [7:0] video_epoch,
    input wire audio_apply,input wire audio_active,
    input wire [1:0] audio_level,input wire [7:0] audio_event_id,
    input wire [7:0] audio_epoch,
    input wire [7:0] panel_seg_n,input wire media_error,
    input wire [7:0] error_seg_n,output wire [7:0] seg_n
);
    wire bundles_match=video_active && audio_active &&
                       video_level==audio_level &&
                       video_event_id==audio_event_id &&
                       video_epoch==audio_epoch;
    wire indicator_on=bundles_match || video_apply || audio_apply;
    wire [7:0] event_seg_n={indicator_on ? 1'b0 : panel_seg_n[7],
                            panel_seg_n[6:0]};
    assign seg_n=media_error ? error_seg_n : event_seg_n;
endmodule
