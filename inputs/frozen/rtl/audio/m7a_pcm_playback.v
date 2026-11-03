// M7-A one-file playback epoch. Orchestrator must stop producers and reset BOTH
// FIFO domains before starting another file; do not reset one pointer alone.
// Existing official show-ahead FIFO remains read-only. One {last, PCM16} sample
// occupies one 17-bit word (no constant upper padding, preserving TD BRAM
// inference). Output tick cadence never stalls: paused/empty ticks are
// silence, but only actual file samples advance the content counter.
module m7a_pcm_playback #(
    parameter integer PREFILL_SAMPLES=128
) (
    input wire wr_clk, input wire rd_clk, input wire rst,
    input wire pcm_valid, output wire pcm_ready,
    input wire signed [15:0] pcm_data, input wire pcm_last,
    input wire sample_tick, input wire play_enable,
    output reg audio_valid,
    output reg signed [23:0] audio_left, output reg signed [23:0] audio_right,
    output reg signed [15:0] played_pcm,
    output reg education_advance, output reg [31:0] played_sample_count,
    output reg stream_end, output reg underflow_sticky,
    output wire [8:0] wr_level, output wire [8:0] rd_level
);
    (* ASYNC_REG="TRUE" *) reg [2:0] wr_release,rd_release;
    wire wr_local_reset = !wr_release[2];
    wire rd_local_reset = !rd_release[2];
    reg write_closed;
    (* ASYNC_REG="TRUE" *) reg closed_sync1,closed_sync2;
    reg primed;
    wire [16:0] word_data;
    wire word_valid,empty,full;
    wire available=word_valid && !empty;
    wire pop=rd_release[2] && sample_tick && play_enable && primed &&
             !stream_end && available;
    assign pcm_ready=wr_release[2] && !rst && !write_closed && !full;
    rfifo_32_32_512 #(.DATA_WIDTH_W(17),.DATA_WIDTH_R(17),.SHOW_AHEAD_EN(1'b1),.OUTREG_EN("NOREG")) u_fifo (
        .rst(rst),.clkw(wr_clk),.clkr(rd_clk),.we(pcm_valid && pcm_ready),
        .di({pcm_last,pcm_data}),.re(pop),.dout(word_data),.valid(word_valid),
        .empty_flag(empty),.full_flag(full),.afull(),.aempty(),
        .wrusedw(wr_level),.rdusedw(rd_level));
    // Raw epoch reset only reaches local release guards and vendor FIFO reset
    // synchronizers. Functional registers release on their own clock domain.
    always @(posedge wr_clk or posedge rst) begin
        if(rst) wr_release<=0;
        else wr_release<={wr_release[1:0],1'b1};
    end
    always @(posedge rd_clk or posedge rst) begin
        if(rst) rd_release<=0;
        else rd_release<={rd_release[1:0],1'b1};
    end
    always @(posedge wr_clk or posedge wr_local_reset) begin
        if(wr_local_reset) write_closed<=0;
        else if(pcm_valid && pcm_ready && pcm_last) write_closed<=1;
    end
    always @(posedge rd_clk or posedge rd_local_reset) begin
        if(rd_local_reset) begin
            closed_sync1<=0;closed_sync2<=0;primed<=0;
            audio_valid<=0;audio_left<=0;audio_right<=0;played_pcm<=0;
            education_advance<=0;played_sample_count<=0;
            stream_end<=0;underflow_sticky<=0;
        end else begin
            closed_sync1<=write_closed;closed_sync2<=closed_sync1;
            if(rd_release[2] && (rd_level>=PREFILL_SAMPLES || (closed_sync2 && available)))
                primed<=1;
            audio_valid<=sample_tick;
            education_advance<=0;
            if(sample_tick) begin
                audio_left<=0;audio_right<=0;played_pcm<=0;
                if(pop) begin
                    played_pcm<=word_data[15:0];
                    audio_left<={word_data[15:0],8'd0};
                    audio_right<={word_data[15:0],8'd0};
                    education_advance<=1;
                    played_sample_count<=played_sample_count+1'b1;
                    if(word_data[16]) stream_end<=1;
                end else if(play_enable && primed && !stream_end && !available)
                    underflow_sticky<=1;
            end
        end
    end
endmodule
