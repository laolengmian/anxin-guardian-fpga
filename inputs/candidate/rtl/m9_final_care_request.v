`timescale 1ns/1ps
// One in-flight theme transaction, one pending human request, and one
// coalesced automatic deadline. KEY6 always has priority and restarts timing.
module m9_final_care_request #(
    // Legacy mode exists only for the unchanged historical arbitration oracles.
    parameter integer WAIT_FOR_NARRATION=1,
    parameter integer NARRATION_TAIL_CYCLES=50000000
) (
    input wire clk,input wire rst,input wire key6_event,
    input wire auto_enable,input wire [31:0] auto_period_cycles,
    input wire controls_enabled,input wire request_complete,
    input wire visible_page_valid,input wire [1:0] visible_page_id,
    input wire narration_done,
    output reg next_image_req,output reg replay_cancel,output reg busy
);
    reg pending;
    reg auto_due;
    reg [31:0] auto_elapsed;
    reg [31:0] tail_elapsed;
    reg [1:0] observed_page;
    reg observed_valid,awaiting_visible;
    wire page_changed=visible_page_valid &&
                      (!observed_valid || observed_page!=visible_page_id);
    wire narration_ready=visible_page_valid && !page_changed &&
        !awaiting_visible && narration_done &&
        tail_elapsed>=NARRATION_TAIL_CYCLES;

    wire completing=busy && request_complete;
    wire auto_now=auto_period_cycles!=0 &&
                  auto_elapsed>=auto_period_cycles-1'b1;
    wire manual_launch=controls_enabled &&
        ((!busy && key6_event) || (completing && (pending || key6_event)));
    wire auto_launch=controls_enabled && auto_enable && !manual_launch &&
        (!busy || completing) && auto_period_cycles!=0 &&
        (auto_due || auto_now) && (!WAIT_FOR_NARRATION || narration_ready);
    wire launch=manual_launch || auto_launch;
    wire restart_timer=!controls_enabled || !auto_enable || launch ||
                       (busy && key6_event) ||
                       (WAIT_FOR_NARRATION && (!visible_page_valid || page_changed));

    always @(posedge clk or posedge rst) begin
        if(rst) begin
            next_image_req<=1'b0;
            replay_cancel<=1'b0;
            busy<=1'b0;
            pending<=1'b0;
        end else begin
            next_image_req<=launch;
            replay_cancel<=launch;
            if(launch)
                busy<=1'b1;
            else if(completing)
                busy<=1'b0;

            if(!controls_enabled || launch || !busy)
                pending<=1'b0;
            else if(key6_event)
                pending<=1'b1;
        end
    end

    // The snapshot contains page identity and consumed EOF atomically. A
    // manager ACK is NOT visibility: after any launch, wait for another page.
    always @(posedge clk or posedge rst) begin
        if(rst) begin
            observed_page<=2'd0;observed_valid<=1'b0;
            awaiting_visible<=1'b0;tail_elapsed<=32'd0;
        end else begin
            observed_valid<=visible_page_valid;
            if(visible_page_valid) observed_page<=visible_page_id;
            if(page_changed || !controls_enabled) awaiting_visible<=1'b0;
            if(launch) awaiting_visible<=1'b1;
            if(restart_timer || !narration_done)
                tail_elapsed<=32'd0;
            else if(tail_elapsed<NARRATION_TAIL_CYCLES)
                tail_elapsed<=tail_elapsed+1'b1;
        end
    end

    always @(posedge clk or posedge rst) begin
        if(rst) begin
            auto_due<=1'b0;
            auto_elapsed<=32'd0;
        end else if(restart_timer) begin
            auto_due<=1'b0;
            auto_elapsed<=32'd0;
        end else begin
            if(auto_now)
                auto_due<=1'b1;
            if(auto_elapsed!=32'hffffffff)
                auto_elapsed<=auto_elapsed+1'b1;
        end
    end
endmodule

// Video-domain status uses the existing four-bit audio-selection handshake.
// Dwell begins at the first display frame boundary presenting the incoming
// wipe identity (the wipe interval is included), never at a queued request.
module m9_care_page_status (
    input wire clk,input wire rst,input wire frame_start,
    input wire page_valid,input wire [1:0] page_id,
    input wire audio_identity_valid,input wire [1:0] audio_id,
    input wire audio_play,input wire education_advance,
    input wire [31:0] played_count,input wire stream_end,
    output wire [3:0] status,output wire status_update
);
    reg visible_valid,eof_armed;
    reg [1:0] visible_page;
    reg [3:0] previous_status;
    wire page_commit=frame_start && page_valid &&
        (!visible_valid || visible_page!=page_id);
    wire matching=visible_valid && audio_identity_valid &&
        audio_id==visible_page && audio_play;
    // One-sample clips assert advance and EOF together. A lingering EOF alone
    // cannot arm a new page, and zero consumed samples never mean completion.
    wire consumed_done=matching && !page_commit && played_count!=0 &&
        stream_end && (eof_armed || education_advance);
    assign status={visible_valid,consumed_done,visible_page};
    assign status_update=status!=previous_status;
    always @(posedge clk or posedge rst) begin
        if(rst) begin
            visible_valid<=1'b0;visible_page<=2'd0;eof_armed<=1'b0;
            previous_status<=4'd0;
        end else begin
            previous_status<=status;
            if(frame_start && page_valid) begin
                visible_valid<=1'b1;visible_page<=page_id;
            end
            if(!page_valid) visible_valid<=1'b0;
            if(page_commit || !matching)
                eof_armed<=1'b0;
            else if(!stream_end || education_advance)
                eof_armed<=1'b1;
        end
    end
endmodule
