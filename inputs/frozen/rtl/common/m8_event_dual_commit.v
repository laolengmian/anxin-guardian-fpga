// M8 immutable event bundle transfer. One bundled-data CDC feeds two distinct
// application boundaries in the destination clock domain; ack returns only
// after both video and audio have applied the same record.
module m8_event_dual_commit (
    input wire src_clk,input wire src_rst,input wire src_update,
    input wire src_event_active,input wire [1:0] src_level,
    input wire [7:0] src_event_id,input wire [7:0] src_epoch,
    (* preserve = "true" *) output reg src_busy,
    (* preserve = "true" *) output reg src_ack_pulse,
    input wire dst_clk,input wire dst_rst,
    input wire video_boundary,input wire audio_boundary,
    output wire video_apply_pulse,
    output wire video_event_active,
    output wire [1:0] video_level,
    output wire [7:0] video_event_id,
    output wire [7:0] video_epoch,
    output wire audio_apply_pulse,
    output wire audio_event_active,
    output wire [1:0] audio_level,
    output wire [7:0] audio_event_id,
    output wire [7:0] audio_epoch
);
    (* keep = "true", preserve = "true" *) reg video_apply_pulse_q;
    (* keep = "true", preserve = "true" *) reg video_event_active_q;
    (* keep = "true", preserve = "true" *) reg [1:0] video_level_q;
    (* keep = "true", preserve = "true" *) reg [7:0] video_event_id_q;
    (* keep = "true", preserve = "true" *) reg [7:0] video_epoch_q;
    (* keep = "true", preserve = "true" *) reg audio_apply_pulse_q;
    (* keep = "true", preserve = "true" *) reg audio_event_active_q;
    (* keep = "true", preserve = "true" *) reg [1:0] audio_level_q;
    (* keep = "true", preserve = "true" *) reg [7:0] audio_event_id_q;
    (* keep = "true", preserve = "true" *) reg [7:0] audio_epoch_q;
    assign video_apply_pulse=video_apply_pulse_q;
    assign video_event_active=video_event_active_q;
    assign video_level=video_level_q;
    assign video_event_id=video_event_id_q;
    assign video_epoch=video_epoch_q;
    assign audio_apply_pulse=audio_apply_pulse_q;
    assign audio_event_active=audio_event_active_q;
    assign audio_level=audio_level_q;
    assign audio_event_id=audio_event_id_q;
    assign audio_epoch=audio_epoch_q;

    (* preserve = "true" *) reg src_request_toggle;
    (* keep = "true", preserve = "true" *) reg src_held_active;
    (* keep = "true", preserve = "true" *) reg [1:0] src_held_level;
    (* keep = "true", preserve = "true" *) reg [7:0] src_held_event_id;
    (* keep = "true", preserve = "true" *) reg [7:0] src_held_epoch;
    (* preserve = "true" *) reg src_pending_valid;
    (* keep = "true", preserve = "true" *) reg src_pending_active;
    (* keep = "true", preserve = "true" *) reg [1:0] src_pending_level;
    (* keep = "true", preserve = "true" *) reg [7:0] src_pending_event_id;
    (* keep = "true", preserve = "true" *) reg [7:0] src_pending_epoch;
    (* ASYNC_REG = "TRUE", preserve = "true" *) reg src_ack_sync_stage1;
    (* ASYNC_REG = "TRUE", preserve = "true" *) reg src_ack_sync_stage2;

    (* ASYNC_REG = "TRUE", preserve = "true" *) reg dst_request_sync_stage1;
    (* ASYNC_REG = "TRUE", preserve = "true" *) reg dst_request_sync_stage2;
    (* preserve = "true" *) reg dst_ack_toggle;
    (* preserve = "true" *) reg dst_pending;
    (* preserve = "true" *) reg dst_video_done,dst_audio_done;
    (* keep = "true", preserve = "true" *) reg dst_pending_active;
    (* keep = "true", preserve = "true" *) reg [1:0] dst_pending_level;
    (* keep = "true", preserve = "true" *) reg [7:0] dst_pending_event_id,dst_pending_epoch;

    wire src_transfer_done=src_busy &&
                           src_ack_sync_stage2==src_request_toggle;
    wire dst_request_waiting=dst_request_sync_stage2!=dst_ack_toggle;

    always @(posedge src_clk or posedge src_rst) begin
        if(src_rst) begin
            src_request_toggle<=0;src_held_active<=0;src_held_level<=0;
            src_held_event_id<=0;src_held_epoch<=0;
            src_pending_valid<=0;src_pending_active<=0;src_pending_level<=0;
            src_pending_event_id<=0;src_pending_epoch<=0;
            src_ack_sync_stage1<=0;src_ack_sync_stage2<=0;
            src_busy<=0;src_ack_pulse<=0;
        end else begin
            src_ack_sync_stage1<=dst_ack_toggle;
            src_ack_sync_stage2<=src_ack_sync_stage1;
            src_ack_pulse<=0;

            if(src_transfer_done) begin
                src_ack_pulse<=1;
                if(src_pending_valid) begin
                    if(src_update && src_level>=src_pending_level) begin
                        src_held_active<=src_event_active;
                        src_held_level<=src_level;
                        src_held_event_id<=src_event_id;
                        src_held_epoch<=src_epoch;
                    end else begin
                        src_held_active<=src_pending_active;
                        src_held_level<=src_pending_level;
                        src_held_event_id<=src_pending_event_id;
                        src_held_epoch<=src_pending_epoch;
                    end
                    src_pending_valid<=0;
                    src_request_toggle<=~src_request_toggle;
                    src_busy<=1;
                end else if(src_update || src_epoch!=src_held_epoch) begin
                    src_held_active<=src_event_active;
                    src_held_level<=src_level;
                    src_held_event_id<=src_event_id;
                    src_held_epoch<=src_epoch;
                    src_request_toggle<=~src_request_toggle;
                    src_busy<=1;
                end else begin
                    src_busy<=0;
                end
            end else if(src_busy) begin
                if(src_update && (!src_pending_valid ||
                                  src_level>=src_pending_level)) begin
                    src_pending_valid<=1;
                    src_pending_active<=src_event_active;
                    src_pending_level<=src_level;
                    src_pending_event_id<=src_event_id;
                    src_pending_epoch<=src_epoch;
                end
            end else if(src_update) begin
                src_held_active<=src_event_active;
                src_held_level<=src_level;
                src_held_event_id<=src_event_id;
                src_held_epoch<=src_epoch;
                src_request_toggle<=~src_request_toggle;
                src_busy<=1;
            end
        end
    end

    always @(posedge dst_clk or posedge dst_rst) begin
        if(dst_rst) begin
            dst_request_sync_stage1<=0;dst_request_sync_stage2<=0;
            dst_ack_toggle<=0;dst_pending<=0;
            dst_video_done<=0;dst_audio_done<=0;
            dst_pending_active<=0;dst_pending_level<=0;
            dst_pending_event_id<=0;dst_pending_epoch<=0;
            video_apply_pulse_q<=0;video_event_active_q<=0;video_level_q<=0;
            video_event_id_q<=0;video_epoch_q<=0;
            audio_apply_pulse_q<=0;audio_event_active_q<=0;audio_level_q<=0;
            audio_event_id_q<=0;audio_epoch_q<=0;
        end else begin
            dst_request_sync_stage1<=src_request_toggle;
            dst_request_sync_stage2<=dst_request_sync_stage1;
            video_apply_pulse_q<=0;audio_apply_pulse_q<=0;

            if(!dst_pending && dst_request_waiting) begin
                dst_pending<=1;
                dst_video_done<=0;dst_audio_done<=0;
                dst_pending_active<=src_held_active;
                dst_pending_level<=src_held_level;
                dst_pending_event_id<=src_held_event_id;
                dst_pending_epoch<=src_held_epoch;
            end else if(dst_pending) begin
                if(video_boundary && !dst_video_done) begin
                    video_event_active_q<=dst_pending_active;
                    video_level_q<=dst_pending_level;
                    video_event_id_q<=dst_pending_event_id;
                    video_epoch_q<=dst_pending_epoch;
                    video_apply_pulse_q<=1;
                    dst_video_done<=1;
                end
                if(audio_boundary && !dst_audio_done) begin
                    audio_event_active_q<=dst_pending_active;
                    audio_level_q<=dst_pending_level;
                    audio_event_id_q<=dst_pending_event_id;
                    audio_epoch_q<=dst_pending_epoch;
                    audio_apply_pulse_q<=1;
                    dst_audio_done<=1;
                end
                if((dst_video_done || video_boundary) &&
                   (dst_audio_done || audio_boundary)) begin
                    dst_ack_toggle<=dst_request_sync_stage2;
                    dst_pending<=0;
                    dst_video_done<=0;dst_audio_done<=0;
                end
            end
        end
    end
endmodule
