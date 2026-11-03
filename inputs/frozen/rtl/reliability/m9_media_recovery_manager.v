// M9-C sys-domain recovery transaction. The manager never drives Health,
// video, HDMI, or PLL resets: it only owns the private media epoch.
module m9_media_recovery_manager #(
    parameter integer QUIET_CYCLES=32,
    parameter integer RESET_CYCLES=8,
    parameter integer RELEASE_CYCLES=8,
    parameter integer RECOVERY_TIMEOUT_CYCLES=250000000,
    parameter integer TIMER_TICK_CYCLES=1
) (
    input wire clk,input wire rst,input wire timer_tick,
    input wire recovery_start,
    input wire reader_request,input wire reader_busy,
    input wire reader_valid,input wire reader_done,
    input wire sd_init_done,input wire sd_init_ready,
    input wire media_done,input wire media_error,input wire audio_error,
    input wire [3:0] image_complete,input wire image_catalog_valid,
    input wire [3:0] audio_catalog_valid,input wire first_frame_confirmed,
    output wire recovery_busy,output wire media_quiesce,
    output reg media_epoch_reset,output reg sd_init_start,
    output reg media_start,output reg recovery_complete,
    output reg recovery_failed,output reg recovery_progress
);
    localparam [2:0] IDLE=3'd0,QUIET=3'd1,EPOCH_RESET=3'd2;
    localparam [2:0] RELEASE=3'd3,WAIT_SD=3'd4,WAIT_MEDIA=3'd5;
    localparam [2:0] WAIT_FRAME=3'd6;
    localparam integer PHASE_COUNT_WIDTH=(QUIET_CYCLES<=1 && RESET_CYCLES<=1 &&
        RELEASE_CYCLES<=1) ? 1 : $clog2(
        (QUIET_CYCLES>RESET_CYCLES ?
            (QUIET_CYCLES>RELEASE_CYCLES ? QUIET_CYCLES : RELEASE_CYCLES) :
            (RESET_CYCLES>RELEASE_CYCLES ? RESET_CYCLES : RELEASE_CYCLES)));
    localparam integer TIMEOUT_USES_RAW=TIMER_TICK_CYCLES<=1 ||
        RECOVERY_TIMEOUT_CYCLES<=TIMER_TICK_CYCLES;
    localparam integer RECOVERY_TIMEOUT_TICKS=TIMEOUT_USES_RAW ?
        RECOVERY_TIMEOUT_CYCLES :
        ((RECOVERY_TIMEOUT_CYCLES-2)/TIMER_TICK_CYCLES)+2;
    localparam integer TIMEOUT_COUNT_WIDTH=RECOVERY_TIMEOUT_TICKS<=1 ? 1 :
                                           $clog2(RECOVERY_TIMEOUT_TICKS);

    reg [2:0] state;
    reg [PHASE_COUNT_WIDTH-1:0] phase_count;
    reg [TIMEOUT_COUNT_WIDTH-1:0] timeout_count;
    reg media_done_seen;
    reg reader_done_q;
    reg [3:0] image_complete_seen;
    reg image_catalog_seen;
    reg [3:0] audio_catalog_seen;
    reg progress_pending;

    wire reader_active=reader_request || reader_busy || reader_valid || reader_done;
    wire catalogs_complete=image_catalog_valid && image_complete==4'hf &&
                           audio_catalog_valid==4'hf;
    wire timeout_step=TIMEOUT_USES_RAW || timer_tick;
    wire timeout_expired=state!=IDLE && timeout_step &&
        (RECOVERY_TIMEOUT_TICKS<=1 ||
         timeout_count>=RECOVERY_TIMEOUT_TICKS-1);

    wire reader_done_event=reader_done && !reader_done_q;
    wire image_complete_progress=|(image_complete & ~image_complete_seen);
    wire image_catalog_progress=image_catalog_valid && !image_catalog_seen;
    wire audio_catalog_progress=|(audio_catalog_valid & ~audio_catalog_seen);
    wire media_done_progress=media_done && !media_done_seen;
    wire wait_media_progress=state==WAIT_MEDIA &&
        ((reader_done_event && !media_done_seen) || image_complete_progress ||
         image_catalog_progress || audio_catalog_progress || media_done_progress);

    wire quiet_advance=state==QUIET && !reader_active &&
        (QUIET_CYCLES<=1 || phase_count>=QUIET_CYCLES-1);
    wire reset_advance=state==EPOCH_RESET &&
        (RESET_CYCLES<=1 || phase_count>=RESET_CYCLES-1);
    wire release_advance=state==RELEASE && !media_epoch_reset &&
        (RELEASE_CYCLES<=1 || phase_count>=RELEASE_CYCLES-1);
    wire sd_advance=state==WAIT_SD && sd_init_done && sd_init_ready;
    wire media_ready=(media_done_seen || media_done) && catalogs_complete;
    wire frame_wait_advance=state==WAIT_MEDIA && media_ready &&
                            !first_frame_confirmed;
    wire watchdog_progress=quiet_advance || reset_advance || release_advance ||
                           sd_advance || wait_media_progress ||
                           frame_wait_advance;

    wire explicit_failure=(state==WAIT_SD && sd_init_done && !sd_init_ready) ||
        ((state==WAIT_MEDIA || state==WAIT_FRAME) &&
         (media_error || audio_error));
    wire terminal_success=(state==WAIT_MEDIA && media_ready &&
                           first_frame_confirmed) ||
                          (state==WAIT_FRAME && first_frame_confirmed);
    wire timeout_failure=timeout_expired && !watchdog_progress;
    wire invalid_state=state>WAIT_FRAME;
    wire manager_result_now=explicit_failure || terminal_success ||
                            timeout_failure || invalid_state;

    assign recovery_busy=state!=IDLE;
    assign media_quiesce=state!=IDLE;

    always @(posedge clk) begin
        if(rst) begin
            state<=IDLE;phase_count<=0;timeout_count<=0;
            media_done_seen<=0;reader_done_q<=0;
            image_complete_seen<=0;image_catalog_seen<=0;
            audio_catalog_seen<=0;progress_pending<=0;
            media_epoch_reset<=0;sd_init_start<=0;media_start<=0;
            recovery_complete<=0;recovery_failed<=0;recovery_progress<=0;
        end else begin
            // Register the multi-bit state decode before it reaches asynchronous
            // reset pins; only this glitch-free Q leaves the manager.
            media_epoch_reset<=state==EPOCH_RESET;
            sd_init_start<=0;media_start<=0;
            recovery_complete<=0;recovery_failed<=0;recovery_progress<=0;
            reader_done_q<=reader_done;

            // The timeout parameter now bounds inactivity. Accepted forward
            // progress clears it immediately, independently of the coarse tick.
            if(state==IDLE || watchdog_progress)
                timeout_count<=0;
            else if(timeout_step && !timeout_expired)
                timeout_count<=timeout_count+1'b1;

            // Local progress may occur much faster than the event CDC contract.
            // Coalesce it and emit at most once per shared timer tick.
            if(state==IDLE || manager_result_now) begin
                progress_pending<=0;
            end else if(timer_tick && (progress_pending || watchdog_progress)) begin
                recovery_progress<=1;
                progress_pending<=0;
            end else if(watchdog_progress) begin
                progress_pending<=1;
            end

            case(state)
                IDLE:begin
                    phase_count<=0;timeout_count<=0;
                    media_done_seen<=0;image_complete_seen<=0;
                    image_catalog_seen<=0;audio_catalog_seen<=0;
                    if(recovery_start) state<=QUIET;
                end
                QUIET:begin
                    if(quiet_advance) begin
                        phase_count<=0;state<=EPOCH_RESET;
                    end else if(timeout_expired) begin
                        recovery_failed<=1;state<=IDLE;
                    end else if(reader_active) begin
                        phase_count<=0;
                    end else begin
                        phase_count<=phase_count+1'b1;
                    end
                end
                EPOCH_RESET:begin
                    if(reset_advance) begin
                        phase_count<=0;state<=RELEASE;
                    end else if(timeout_expired) begin
                        recovery_failed<=1;state<=IDLE;
                    end else begin
                        phase_count<=phase_count+1'b1;
                    end
                end
                RELEASE:begin
                    if(release_advance) begin
                        phase_count<=0;sd_init_start<=1;state<=WAIT_SD;
                    end else if(timeout_expired) begin
                        recovery_failed<=1;state<=IDLE;
                    end else if(media_epoch_reset) begin
                        // The registered decoder deasserts on this first RELEASE
                        // edge. Start the configured release interval afterward.
                        phase_count<=0;
                    end else begin
                        phase_count<=phase_count+1'b1;
                    end
                end
                WAIT_SD:begin
                    if(sd_init_done && !sd_init_ready) begin
                        recovery_failed<=1;state<=IDLE;
                    end else if(sd_advance) begin
                        media_done_seen<=0;
                        image_complete_seen<=image_complete;
                        image_catalog_seen<=image_catalog_valid;
                        audio_catalog_seen<=audio_catalog_valid;
                        media_start<=1;state<=WAIT_MEDIA;
                    end else if(timeout_expired) begin
                        recovery_failed<=1;state<=IDLE;
                    end
                end
                WAIT_MEDIA:begin
                    image_complete_seen<=image_complete_seen | image_complete;
                    image_catalog_seen<=image_catalog_seen | image_catalog_valid;
                    audio_catalog_seen<=audio_catalog_seen | audio_catalog_valid;
                    if(media_done_progress)
                        media_done_seen<=1;
                    if(media_error || audio_error) begin
                        recovery_failed<=1;state<=IDLE;
                    end else if(media_ready) begin
                        if(first_frame_confirmed) begin
                            recovery_complete<=1;state<=IDLE;
                        end else begin
                            state<=WAIT_FRAME;
                        end
                    end else if(wait_media_progress) begin
                        // The shared inactivity counter was rearmed above.
                    end else if(timeout_expired) begin
                        recovery_failed<=1;state<=IDLE;
                    end
                end
                WAIT_FRAME:begin
                    if(media_error || audio_error) begin
                        recovery_failed<=1;state<=IDLE;
                    end else if(first_frame_confirmed) begin
                        recovery_complete<=1;state<=IDLE;
                    end else if(timeout_expired) begin
                        recovery_failed<=1;state<=IDLE;
                    end
                end
                default:begin
                    recovery_failed<=1;state<=IDLE;
                end
            endcase
        end
    end
endmodule
