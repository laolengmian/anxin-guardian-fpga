// U6 same-Bank audio replay timer. A sticky consumed-EOF level starts one
// bounded wait; EOF must return low in a new audio epoch before it can re-arm.
module m9_audio_replay_controller #(
    parameter integer DELAY_TICKS=10000
) (
    input wire clk,input wire rst,input wire timer_tick,input wire eof_sync,
    input wire [1:0] current_bank,input wire [1:0] desired_bank,
    input wire key_next,input wire safe_pause,input wire media_quiesce,
    input wire media_epoch_reset,input wire audio_error,input wire replay_accept,
    output reg replay_request
);
    localparam integer COUNTER_WIDTH=DELAY_TICKS<=1 ? 1 : $clog2(DELAY_TICKS);
    reg waiting,eof_armed;
    reg [1:0] eof_bank;
    reg [COUNTER_WIDTH-1:0] tick_count;
    wire cancel=key_next || safe_pause || media_quiesce ||
                media_epoch_reset || audio_error;
    wire bank_changed=current_bank!=eof_bank || desired_bank!=eof_bank;

    always @(posedge clk or posedge rst) begin
        if(rst) begin
            replay_request<=1'b0;waiting<=1'b0;eof_armed<=1'b0;
            eof_bank<=2'd0;tick_count<={COUNTER_WIDTH{1'b0}};
        end else if(cancel) begin
            replay_request<=1'b0;waiting<=1'b0;eof_armed<=1'b0;
            eof_bank<=current_bank;tick_count<={COUNTER_WIDTH{1'b0}};
        end else begin
            if(!eof_sync)
                eof_armed<=1'b1;
            if(replay_request) begin
                if(bank_changed) begin
                    replay_request<=1'b0;eof_armed<=1'b0;tick_count<={COUNTER_WIDTH{1'b0}};
                end else if(replay_accept) begin
                    replay_request<=1'b0;eof_armed<=1'b0;tick_count<={COUNTER_WIDTH{1'b0}};
                end
            end else if(waiting) begin
                if(bank_changed) begin
                    waiting<=1'b0;eof_armed<=1'b0;tick_count<={COUNTER_WIDTH{1'b0}};
                end else if(timer_tick) begin
                    if(tick_count==DELAY_TICKS-1) begin
                        waiting<=1'b0;replay_request<=1'b1;tick_count<={COUNTER_WIDTH{1'b0}};
                    end else
                        tick_count<=tick_count+1'b1;
                end
            end else if(eof_sync && eof_armed) begin
                eof_armed<=1'b0;tick_count<={COUNTER_WIDTH{1'b0}};
                eof_bank<=current_bank;
                if(current_bank==desired_bank)
                    waiting<=1'b1;
            end
        end
    end
endmodule
