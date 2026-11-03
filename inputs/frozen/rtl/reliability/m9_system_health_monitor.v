// M9 policy core in the independent 50MHz health domain. Every input must
// already be synchronized, acknowledged, or snapshot-committed into clk.
// audio_pll_lock is a semantic status bit tied to the physical HDMI PLL in top.
module m9_system_health_monitor #(
    parameter integer BOOT_TIMEOUT_CYCLES=250000000,
    parameter integer HEALTHY_CONFIRM_CYCLES=2500000,
    parameter integer FIFO_WARN_SAMPLES=3,
    parameter [9:0] READ_LOW_LEVEL=10'd8,
    parameter [8:0] WRITE_HIGH_LEVEL=9'd504,
    parameter [8:0] PCM_LOW_LEVEL=9'd2
) (
    input wire clk,input wire rst,
    input wire sys_pll_lock,input wire video_pll_lock,input wire audio_pll_lock,
    input wire sd_init_done,input wire sdram_init_done,
    input wire video_alive,input wire video_timeout_active,input wire video_timeout_pulse,
    input wire audio_expected,input wire pcm_expected,input wire audio_alive,
    input wire audio_timeout_active,input wire audio_timeout_pulse,
    input wire read_expected,input wire write_expected,
    input wire read_snapshot_valid,input wire [9:0] read_fifo_level,
    input wire write_snapshot_valid,input wire [8:0] write_fifo_level,
    input wire pcm_snapshot_valid,input wire [8:0] pcm_fifo_level,
    input wire read_underflow_event,input wire write_overflow_event,input wire pcm_underflow_event,
    input wire media_error_event,input wire media_error_active,
    input wire [2:0] media_error_stage,input wire [7:0] media_error_code,
    input wire recovery_active,input wire recovery_complete,
    input wire [3:0] media_state,input wire [1:0] failsafe_state,
    output reg [1:0] health_status,
    output wire [2:0] pll_status,output wire [1:0] init_status,output wire [1:0] heartbeat_status,
    output reg [9:0] read_fifo_snapshot,output reg [8:0] write_fifo_snapshot,
    output reg [8:0] pcm_fifo_snapshot,output reg [2:0] snapshot_valid,
    output wire [3:0] media_state_out,output wire [1:0] failsafe_state_out,
    output reg [7:0] last_error_code,output reg [2:0] last_media_error_stage,
    output reg [7:0] last_media_error_code,
    output reg [15:0] error_count,
    output wire [2:0] fifo_warning_status,output wire [7:0] degraded_reason,
    output wire safe_request,output wire boot_ready
);
    localparam [1:0] HEALTHY=2'd0,DEGRADED=2'd1,FAULT=2'd2;
    localparam [7:0] ERR_VIDEO_PLL=8'h90,ERR_SYS_PLL=8'h91,ERR_AUDIO_PLL=8'h92;
    localparam [7:0] ERR_SDRAM_INIT=8'h93,ERR_VIDEO_HEARTBEAT=8'h94;
    localparam [7:0] ERR_AUDIO_HEARTBEAT=8'h95,ERR_READ_UNDERFLOW=8'h96;
    localparam [7:0] ERR_WRITE_OVERFLOW=8'h97,ERR_PCM_UNDERFLOW=8'h98;
    localparam [7:0] ERR_MEDIA=8'h99,ERR_SD_INIT=8'h9a;
    reg boot_ready_seen,boot_timed_out,fault_latched;
    reg [31:0] boot_count,healthy_count;
    reg [15:0] read_warn_count,write_warn_count,pcm_warn_count;
    reg read_warn_active,write_warn_active,pcm_warn_active;
    reg infrastructure_fault_q,video_timeout_q,audio_timeout_q;
    reg read_underflow_q,write_overflow_q,pcm_underflow_q,media_error_q;
    wire infrastructure_ready=sys_pll_lock && video_pll_lock && audio_pll_lock &&
                              sd_init_done && sdram_init_done;
    wire infrastructure_fault=boot_timed_out || (boot_ready_seen && !infrastructure_ready);
    wire video_fault=boot_ready_seen && video_timeout_active;
    wire audio_fault=boot_ready_seen && audio_expected && audio_timeout_active;
    wire read_underflow_active=boot_ready_seen && read_expected && read_underflow_event;
    wire write_overflow_active=boot_ready_seen && write_expected && write_overflow_event;
    wire pcm_underflow_active=boot_ready_seen && pcm_expected && pcm_underflow_event;
    wire read_underflow_rise=read_underflow_active && !read_underflow_q;
    wire write_overflow_rise=write_overflow_active && !write_overflow_q;
    wire pcm_underflow_rise=pcm_underflow_active && !pcm_underflow_q;
    wire media_error_rise=media_error_event && !media_error_q;
    wire infrastructure_fault_rise=infrastructure_fault && !infrastructure_fault_q;
    wire video_timeout_rise=boot_ready_seen && ((video_timeout_pulse && !video_timeout_q) ||
                            (video_fault && !video_timeout_q));
    wire audio_timeout_rise=boot_ready_seen && audio_expected &&
                            ((audio_timeout_pulse && !audio_timeout_q) ||
                            (audio_fault && !audio_timeout_q));
    wire current_fault=infrastructure_fault || video_fault || audio_fault || media_error_active ||
                       read_underflow_active || write_overflow_active || pcm_underflow_active;
    wire [3:0] fault_event_count={3'd0,infrastructure_fault_rise}+
                                 {3'd0,video_timeout_rise}+{3'd0,audio_timeout_rise}+
                                 {3'd0,read_underflow_rise}+{3'd0,write_overflow_rise}+
                                 {3'd0,pcm_underflow_rise}+{3'd0,media_error_rise};
    wire fault_event=|fault_event_count;
    wire fifo_warning=read_warn_active || write_warn_active || pcm_warn_active;
    wire liveness_ready=video_alive && (!audio_expected || audio_alive);
    wire qualification_ok=boot_ready_seen && liveness_ready && !recovery_active &&
                          !fifo_warning && !current_fault && !fault_latched;
    reg [7:0] selected_error_code;
    // Current SAFE reason priority: HDMI/video, system/SDRAM, FIFO, media, audio.
    always @* begin
        if(infrastructure_fault && !video_pll_lock) selected_error_code=ERR_VIDEO_PLL;
        else if(infrastructure_fault && !audio_pll_lock) selected_error_code=ERR_AUDIO_PLL;
        else if(video_timeout_rise) selected_error_code=ERR_VIDEO_HEARTBEAT;
        else if(infrastructure_fault && !sys_pll_lock) selected_error_code=ERR_SYS_PLL;
        else if(infrastructure_fault && !sdram_init_done) selected_error_code=ERR_SDRAM_INIT;
        else if(read_underflow_rise) selected_error_code=ERR_READ_UNDERFLOW;
        else if(write_overflow_rise) selected_error_code=ERR_WRITE_OVERFLOW;
        else if(pcm_underflow_rise) selected_error_code=ERR_PCM_UNDERFLOW;
        else if(media_error_rise) selected_error_code=ERR_MEDIA;
        else if(infrastructure_fault && !sd_init_done) selected_error_code=ERR_SD_INIT;
        else selected_error_code=ERR_AUDIO_HEARTBEAT;
    end
    assign pll_status={audio_pll_lock,video_pll_lock,sys_pll_lock};
    assign init_status={sdram_init_done,sd_init_done};
    assign heartbeat_status={audio_alive,video_alive};
    assign media_state_out=media_state;
    assign failsafe_state_out=failsafe_state;
    assign fifo_warning_status={read_warn_active,write_warn_active,pcm_warn_active};
    assign degraded_reason={
        !boot_ready_seen,recovery_active,read_warn_active,write_warn_active,
        pcm_warn_active,boot_ready_seen && !video_alive,
        boot_ready_seen && audio_expected && !audio_alive,
        qualification_ok && healthy_count<HEALTHY_CONFIRM_CYCLES
    };
    assign safe_request=fault_latched || current_fault;
    assign boot_ready=boot_ready_seen;
    always @* begin
        if(safe_request) health_status=FAULT;
        else if(!boot_ready_seen || recovery_active || fifo_warning ||
                healthy_count<HEALTHY_CONFIRM_CYCLES) health_status=DEGRADED;
        else health_status=HEALTHY;
    end
    always @(posedge clk) begin
        if(rst) begin
            boot_ready_seen<=0;boot_timed_out<=0;boot_count<=0;healthy_count<=0;
            fault_latched<=0;last_error_code<=0;last_media_error_stage<=0;
            last_media_error_code<=0;error_count<=0;
            read_fifo_snapshot<=0;write_fifo_snapshot<=0;pcm_fifo_snapshot<=0;snapshot_valid<=0;
            read_warn_count<=0;write_warn_count<=0;pcm_warn_count<=0;
            read_warn_active<=0;write_warn_active<=0;pcm_warn_active<=0;
            infrastructure_fault_q<=0;video_timeout_q<=0;audio_timeout_q<=0;
            read_underflow_q<=0;write_overflow_q<=0;pcm_underflow_q<=0;media_error_q<=0;
        end else begin
            if(!boot_ready_seen && infrastructure_ready) begin
                boot_ready_seen<=1;
                boot_timed_out<=0;
            end
            if(!boot_ready_seen && !boot_timed_out && !infrastructure_ready) begin
                if(BOOT_TIMEOUT_CYCLES<=1 || boot_count>=BOOT_TIMEOUT_CYCLES-1)
                    boot_timed_out<=1;
                else boot_count<=boot_count+1'b1;
            end
            if(qualification_ok) begin
                if(healthy_count<HEALTHY_CONFIRM_CYCLES) healthy_count<=healthy_count+1'b1;
            end else healthy_count<=0;
            if(!read_expected) begin read_warn_count<=0;read_warn_active<=0;end
            else if(read_snapshot_valid) begin
                read_fifo_snapshot<=read_fifo_level;snapshot_valid[2]<=1;
                if(read_fifo_level<=READ_LOW_LEVEL) begin
                    if(read_warn_count<FIFO_WARN_SAMPLES) read_warn_count<=read_warn_count+1'b1;
                    if(FIFO_WARN_SAMPLES<=1 || read_warn_count>=FIFO_WARN_SAMPLES-1) read_warn_active<=1;
                end else begin read_warn_count<=0;read_warn_active<=0;end
            end
            if(!write_expected) begin write_warn_count<=0;write_warn_active<=0;end
            else if(write_snapshot_valid) begin
                write_fifo_snapshot<=write_fifo_level;snapshot_valid[1]<=1;
                if(write_fifo_level>=WRITE_HIGH_LEVEL) begin
                    if(write_warn_count<FIFO_WARN_SAMPLES) write_warn_count<=write_warn_count+1'b1;
                    if(FIFO_WARN_SAMPLES<=1 || write_warn_count>=FIFO_WARN_SAMPLES-1) write_warn_active<=1;
                end else begin write_warn_count<=0;write_warn_active<=0;end
            end
            if(!pcm_expected) begin pcm_warn_count<=0;pcm_warn_active<=0;end
            else if(pcm_snapshot_valid) begin
                pcm_fifo_snapshot<=pcm_fifo_level;snapshot_valid[0]<=1;
                if(pcm_fifo_level<=PCM_LOW_LEVEL) begin
                    if(pcm_warn_count<FIFO_WARN_SAMPLES) pcm_warn_count<=pcm_warn_count+1'b1;
                    if(FIFO_WARN_SAMPLES<=1 || pcm_warn_count>=FIFO_WARN_SAMPLES-1) pcm_warn_active<=1;
                end else begin pcm_warn_count<=0;pcm_warn_active<=0;end
            end
            if(fault_event) begin
                fault_latched<=1;last_error_code<=selected_error_code;
                if(media_error_rise) begin
                    last_media_error_stage<=media_error_stage;
                    last_media_error_code<=media_error_code;
                end
                if(error_count>=16'hffff-fault_event_count) error_count<=16'hffff;
                else error_count<=error_count+fault_event_count;
            end else if(current_fault) fault_latched<=1;
            else if(recovery_complete) begin
                fault_latched<=0;last_error_code<=0;last_media_error_stage<=0;
                last_media_error_code<=0;
            end
            infrastructure_fault_q<=infrastructure_fault;
            video_timeout_q<=boot_ready_seen && (video_fault || video_timeout_pulse);
            audio_timeout_q<=boot_ready_seen && audio_expected &&
                             (audio_fault || audio_timeout_pulse);
            read_underflow_q<=read_underflow_active;
            write_overflow_q<=write_overflow_active;
            pcm_underflow_q<=pcm_underflow_active;
            media_error_q<=media_error_event;
        end
    end
endmodule
