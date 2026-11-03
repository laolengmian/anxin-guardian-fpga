`timescale 1ns/1ps


// =============================================================================


// Independent simplified six-key carousel candidate with bounded media recovery


// Date: 2026-09-28


// =============================================================================


//


// The storage layers follow the 米处 SD -> sector replay -> FAT32 -> BMP


// architecture. PIC1.BMP..PIC4.BMP are preloaded once into the four existing


// RGB565 banks. The v17 reset, HDMI_B, FIFO-valid and whole-burst refresh-budget


// paths remain intact; no TF-card write path exists.


//


// 数据通路：


//   SD SPI/FAT32 -> bmp24_720p_pixel_source -> frame_loader_4bank_v2


//   -> frame_read_write_rgb565（官方frame_fifo_read/write保持原样）


//   -> sdram（官方硬核封装/仿真用sdram_app_sim）


//   -> frame_reader_4bank_v5_fifo_valid


//   -> video_axis_source_4bank -> aligned brightness/OSD -> compositor -> HDMI_B


//


// Storage/control logic is in the 100 MHz system domain. Every pulse crossing,


// including M9-C recovery request/results, uses an explicit event toggle.


// =============================================================================





`include "global_def.v"





module top_4bank_720p_m9_final_candidate #(


    // 时序参数透传（默认720p）


    parameter integer H_ACT  = `H_ACTIVE,


    parameter integer H_FP   = `H_FP,


    parameter integer H_SYNC = `H_SYNC,


    parameter integer H_BP   = `H_BP,


    parameter integer V_ACT  = `V_ACTIVE,


    parameter integer V_FP   = `V_FP,


    parameter integer V_SYNC = `V_SYNC,


    parameter integer V_BP   = `V_BP,


    parameter integer LOCK_STABLE_CYCLES = 1000000,


    parameter integer SD_INIT_STARTUP_CYCLES = 10000000,


    parameter integer KEY_DEBOUNCE_CYCLES = 1000000,


    parameter integer KEY_BRIGHTNESS_HOLD_CYCLES = 50000000,


    parameter integer M8_SWITCH_STABLE_CYCLES = 100000,


    parameter integer M9_CONTROL_TICK_CYCLES = 50000,


    parameter integer M9_MEDIA_RETRY_DELAY_CYCLES = 50000000,


    parameter integer M9_MEDIA_POLICY_TIMEOUT_CYCLES = 250000000,


    parameter integer M9_MEDIA_RECOVERY_TIMEOUT_CYCLES = 400000000,


    parameter integer M9_AUDIO_REPLAY_DELAY_TICKS = 10000,


    parameter integer M9_MAX_RECOVERY_RETRIES = 3,


    // Minimum visible-page dwell; consumed narration EOF and tail also gate auto-next.


    parameter integer M9_CAROUSEL_PERIOD_CYCLES = 800000000


) (


    // Clock and reset


    input  wire        clk_50m,            // 50MHz板载晶振（官方SDC: 20ns周期）


    input  wire        sys_rst_n,          // 系统复位（低有效）





    // User controls


    input  wire        key_next,           // 旧板载KEY2：候选中保留端口但不参与控制


    input  wire        key_auto,           // 旧板载KEY4：候选中保留端口但不参与控制


    input  wire        key1_n,             // 外接KEY1：亮度+


    input  wire        key2_n,             // 外接KEY2：亮度-


    input  wire        key3_n,             // 外接KEY3：音量+


    input  wire        key4_n,             // 外接KEY4：音量-


    input  wire        key5_n,             // 外接KEY5：自动轮播开关，默认关闭


    input  wire        key6_n,             // 外接KEY6：下一护理主题


    input  wire        sw_warning,          // SW1/C8, active high


    input  wire        sw_emergency,        // SW2/C7, active high


    input  wire        sw_diagnostic,       // SW3/C6：保留，极性确认前不接复位





    // 板级IO：EG4S20的SDRAM为封装内硬核（EG_PHY_SDRAM_2M_32，无外部引脚）


    // HDMI_B输出（LVDS33差分对，仅需约束P端；DDC为LVCMOS33）


    output wire        HDMI_CLK_P,


    output wire        HDMI_D2_P,


    output wire        HDMI_D1_P,


    output wire        HDMI_D0_P,


    output wire        HDMI_DDC_SCL,


    inout  wire        HDMI_DDC_SDA,


    inout  wire        vital_i2c_scl,


    inout  wire        vital_i2c_sda,





    // Debug outputs


    output wire [7:0]  seg7_cathode,


    output wire [5:0]  seg7_anode,


    output wire        led_startup_50m,    // LED1/A4, active high; diagnostic only





    // Read-only TF/SD SPI interface


    output wire        sd_ncs,


    output wire        sd_dclk,


    output wire        sd_mosi,


    input  wire        sd_miso


);





    // =========================================================================


    // PLL: 50MHz crystal -> sys/mem/video clocks


    // =========================================================================


    wire clk_125m_mem;      // 125 MHz SDRAM mem_clk   (sys_pll C1)


    wire clk_125m_mem_sft;  // 125 MHz @180° Clk_sft   (sys_pll C2)


    wire clk_75m;           // 75 MHz video clock      (HDMI PLL C0)


    wire clk_100m_sys;      // 100 MHz system/write    (sys_pll C0)


    wire clk_375m_hdmi;     // 375 MHz HDMI 5x serial  (HDMI PLL C1)


    wire clk_audio_mclk;    // audio master clock      (HDMI PLL C2)


    wire sys_clocks_ready,video_clocks_ready;


    wire sys_pll_locked,hdmi_pll_lock;


    reg [31:0] lock_tick_count_50m;


    reg lock_tick_50m;


    reg [31:0] control_tick_count_sys;





    // A2-only 1 ms cadence for lock qualification; this is not a Health domain.


    always @(posedge clk_50m) begin


        if(!sys_rst_n) begin


            lock_tick_count_50m<=0;


            lock_tick_50m<=0;


        end else begin


            lock_tick_50m<=0;


            if(M9_CONTROL_TICK_CYCLES<=1 ||


               lock_tick_count_50m>=M9_CONTROL_TICK_CYCLES-1) begin


                lock_tick_count_50m<=0;


                lock_tick_50m<=1;


            end else begin


                lock_tick_count_50m<=lock_tick_count_50m+1'b1;


            end


        end


    end





`ifdef SIMULATION


    // 仿真：单时钟占位（协议功能与绝对频率无关，tb_datapath_v2 已验证）


    assign clk_100m_sys     = clk_50m;


    assign clk_125m_mem     = clk_50m;


    assign clk_125m_mem_sft = ~clk_50m;


    assign clk_75m          = clk_50m;


    assign clk_375m_hdmi    = clk_50m;


    assign clk_audio_mclk   = clk_50m;


    assign sys_pll_locked   = sys_rst_n;


    assign hdmi_pll_lock    = sys_rst_n;


    assign sys_clocks_ready = sys_rst_n;


    assign video_clocks_ready = sys_rst_n;


`else


    // 综合：真实PLL（sys_pll=官方125M三输出；PLL_HDMI_AUDIO=M6-A已验证）


    sys_pll u_sys_pll (


        .refclk  (clk_50m),


        .reset   (1'b0),              // M6-A官方同款：PLL从不复位（复位由reset_sync链管理）


        .extlock (sys_pll_locked),


        .clk0_out(clk_100m_sys),      // 100 MHz


        .clk1_out(clk_125m_mem),      // 125 MHz


        .clk2_out(clk_125m_mem_sft)   // 125 MHz @180°


    );





    PLL_HDMI_AUDIO u_hdmi_pll (


        .refclk  (clk_50m),


        .reset   (1'b0),              // M6-A官方同款：PLL从不复位（已板测验证的接法）


        .extlock (hdmi_pll_lock),


        .clk0_out(clk_75m),           // 75 MHz（720p像素时钟）


        .clk1_out(clk_375m_hdmi),     // 375 MHz（HDMI 5x串行时钟）


        .clk2_out(clk_audio_mclk)     // 音频主时钟


    );





    // M9-C qualifies the two generated-clock families independently. A


    // system PLL fault cannot remove the HDMI clock used by the local SAFE


    // page; an HDMI PLL fault does not reset the read-only media service.


    m9_split_lock_qualifier #(


        .LOCK_STABLE_CYCLES(LOCK_STABLE_CYCLES),


        .TIMER_TICK_CYCLES(M9_CONTROL_TICK_CYCLES)


    ) u_split_lock_qualifier (


        .clk_50m(clk_50m),.ext_rst_n(sys_rst_n),


        .timer_tick(lock_tick_50m),


        .sys_pll_lock(sys_pll_locked),.video_pll_lock(hdmi_pll_lock),


        .sys_ready(sys_clocks_ready),.video_ready(video_clocks_ready)


    );


`endif





    // =========================================================================


    // Reset Qualification（与已板测通过的M6-A逐结构对齐）


    // =========================================================================


    // 原始外部复位/对应PLL失锁只负责各自时钟族的异步置位；两个独立


    // ready仅进入各目标域release_stage1，release_stage2同步撤销功能复位。


    wire [5:0] external_key_press,external_key_pressed;





    wire sys_fault_assert_async=~sys_rst_n | ~sys_pll_locked;


    wire video_fault_assert_async=~sys_rst_n | ~hdmi_pll_lock;


    wire sys_reset_assert_async=sys_fault_assert_async;


    wire mem_reset_assert_async=sys_fault_assert_async;


    wire video_reset_assert_async=video_fault_assert_async;


    wire hdmi_reset_assert_async=video_fault_assert_async;


    wire audio_reset_assert_async=video_fault_assert_async;


    wire serial_reset_assert_async=video_fault_assert_async;


    wire rst_sys;


    wire rst_mem;


    wire rst_video;


    wire rst_hdmi;


    wire rst_audio;


    wire rst_hdmi_serial;





    qualified_reset_sync u_sys_reset_release (


        .clk           (clk_100m_sys),


        .async_assert (sys_reset_assert_async),


        .release_async(sys_clocks_ready),


        .reset_out     (rst_sys)


    );





    qualified_reset_sync u_mem_reset_release (


        .clk           (clk_125m_mem),


        .async_assert (mem_reset_assert_async),


        .release_async(sys_clocks_ready),


        .reset_out     (rst_mem)


    );





    qualified_reset_sync u_video_reset_release (


        .clk           (clk_75m),


        .async_assert (video_reset_assert_async),


        .release_async(video_clocks_ready),


        .reset_out     (rst_video)


    );





    qualified_reset_sync u_hdmi_reset_release (


        .clk           (clk_75m),


        .async_assert (hdmi_reset_assert_async),


        .release_async(video_clocks_ready),


        .reset_out     (rst_hdmi)


    );





    qualified_reset_sync u_audio_reset_release (


        .clk           (clk_audio_mclk),


        .async_assert (audio_reset_assert_async),


        .release_async(video_clocks_ready),


        .reset_out     (rst_audio)


    );





    qualified_reset_sync u_hdmi_serial_reset_release (


        .clk           (clk_375m_hdmi),


        .async_assert (serial_reset_assert_async),


        .release_async(video_clocks_ready),


        .reset_out     (rst_hdmi_serial)


    );





    wire sys_rst_n_sync   = ~rst_sys;


    wire video_rst_n_sync = ~rst_video;


    wire recovery_start_sys,recovery_complete_sys,recovery_failed_sys;


    wire recovery_progress_sys;


    reg recovery_timeout_tick_sys;


    wire media_recovery_busy_sys,media_quiesce_sys,media_epoch_reset_sys;


    wire recovery_sd_init_start,recovery_media_start;


    wire recovery_frame_boundary_sys;


    wire rst_media;


    wire media_rst_n=~rst_media;


    wire safe_pause_sys;


    wire media_controls_enabled=!safe_pause_sys && !media_quiesce_sys;


    qualified_reset_sync u_media_reset_release (


        .clk(clk_100m_sys),


        .async_assert(rst_sys || media_epoch_reset_sys),


        .release_async(!media_epoch_reset_sys),


        .reset_out(rst_media)


    );


    wire rst_manager_video_epoch;


    wire manager_video_epoch_rst_n=~rst_manager_video_epoch;


    wire rst_identity_video=rst_video || rst_manager_video_epoch;


    qualified_reset_sync u_manager_video_epoch_reset_release (


        .clk(clk_75m),


        .async_assert(rst_media),


        .release_async(!rst_media && video_clocks_ready),


        .reset_out(rst_manager_video_epoch)


    );





    // =========================================================================


    // Video Timing Generator (75MHz video clock)


    // =========================================================================


    wire        de;


    wire [11:0] pixel_x, pixel_y;


    wire        frame_start;





    video_timing_ctrl #(


        .H_ACT(H_ACT), .H_FP(H_FP), .H_SYNC(H_SYNC), .H_BP(H_BP),


        .V_ACT(V_ACT), .V_FP(V_FP), .V_SYNC(V_SYNC), .V_BP(V_BP),


        .ACTIVE_LAST(1'b0)


    ) u_timing (


        .pclk(clk_75m),


        .rst_n(video_rst_n_sync),


        .hsync(),


        .vsync(),


        .de(de),


        .x(pixel_x),


        .y(pixel_y),


        .frame_start(frame_start),


        .line_end()


    );


    wire frame_blank;





    // 垂直消隐起始脉冲：只在最后一条有效行的de下降沿产生。


    // 旧实现仅用de_q&~de，导致每条水平行尾都可能提交Bank；manager随即释放


    // 旧Bank并重写，而reader仍可能在读该帧剩余行，板上表现为持久花点。


    reg de_q;


    assign frame_blank = de_q & ~de & (pixel_y == V_ACT - 1);


    always @(posedge clk_75m or negedge video_rst_n_sync) begin


        if (!video_rst_n_sync) de_q <= 1'b0;


        else                   de_q <= de;


    end





    // =========================================================================


    // 4-Bank Frame Manager（sys_clk域调度 + video_clk域bank提交）


    // =========================================================================


    wire [1:0] display_bank;


    wire [1:0] bank0_state, bank1_state, bank2_state, bank3_state;


    reg banks_initialized_sys;





    reg  [3:0] bank_load_complete;


    reg  [3:0] bank_load_error;


    wire [1:0] next_load_bank;


    wire       start_load;


    wire       ld_complete, ld_error;      // loader完成/出错脉冲（下方声明区）


    wire [1:0] load_bank_active;





    // The two legacy onboard media-control ports remain interface-only. Only the


    // independently debounced external KEY6 can request a care-theme change.





    // A2 resets all six debounce channels. KEY5 is only a press-event toggle.


    wire rst_final_keys;


    qualified_reset_sync u_final_keys_reset_release (


        .clk(clk_100m_sys),.async_assert(~sys_rst_n),


        .release_async(sys_clocks_ready),.reset_out(rst_final_keys)


    );


    m9_final_key_frontend #(


        .STABLE_CYCLES(KEY_DEBOUNCE_CYCLES)


    ) u_final_keys(


        .clk(clk_100m_sys),.rst(rst_final_keys),


        .key_n_async({key6_n,key5_n,key4_n,key3_n,key2_n,key1_n}),


        .press_pulse(external_key_press),.stable_pressed(external_key_pressed));


    wire [3:0] brightness_level_sys,volume_level_sys;


    wire brightness_update_sys,volume_update_sys;


    wire brightness_event_sys=brightness_update_sys;


    m9_final_level_control u_final_levels(


        .clk(clk_100m_sys),.rst(rst_sys),


        .brightness_up(external_key_press[0]),.brightness_down(external_key_press[1]),


        .volume_up(external_key_press[2]),.volume_down(external_key_press[3]),


        .brightness_level(brightness_level_sys),.volume_level(volume_level_sys),


        .brightness_update(brightness_update_sys),.volume_update(volume_update_sys));





    reg auto_carousel_enable,auto_carousel_previous;


    always @(posedge clk_100m_sys or posedge rst_sys) begin


        if(rst_sys) begin auto_carousel_enable<=1'b0;auto_carousel_previous<=1'b0;end


        else begin


            auto_carousel_previous<=auto_carousel_enable;


            if(external_key_press[4]) auto_carousel_enable<=~auto_carousel_enable;


        end


    end





    wire rst_care_sys;


    qualified_reset_sync u_care_reset_release (


        .clk(clk_100m_sys),


        .async_assert(rst_sys || video_fault_assert_async || media_epoch_reset_sys),


        .release_async(!video_fault_assert_async && !media_epoch_reset_sys),


        .reset_out(rst_care_sys)


    );


    wire care_controls_enabled=media_controls_enabled && banks_initialized_sys;


    wire care_next_request,care_replay_cancel,care_request_busy;


    wire care_switch_complete_sys;


    wire [3:0] audio_desired_level_sys;


    m9_final_care_request u_care_request(


        .clk(clk_100m_sys),.rst(rst_care_sys),


        .key6_event(external_key_press[5]),


        .auto_enable(auto_carousel_enable),


        .auto_period_cycles(M9_CAROUSEL_PERIOD_CYCLES),


        .controls_enabled(care_controls_enabled),


        .request_complete(care_switch_complete_sys),


        .visible_page_valid(audio_desired_level_sys[3]),


        .visible_page_id(audio_desired_level_sys[1:0]),


        .narration_done(audio_desired_level_sys[2]),


        .next_image_req(care_next_request),


        .replay_cancel(care_replay_cancel),.busy(care_request_busy));





    m9_final_frame_manager_4bank u_frame_manager (


        .sys_clk(clk_100m_sys),


        .sys_rst_n(media_rst_n),


        .next_image_req(care_next_request),


        .auto_play_enable(1'b0),


        .auto_period_cycles(32'd0),  // Arbitration and timing live in care-request


        .bank_load_complete(bank_load_complete),


        .bank_load_error(bank_load_error),


        .next_load_bank(next_load_bank),


        .start_load(start_load),


        .video_clk(clk_75m),


        .video_rst_n(video_rst_n_sync),


        .video_epoch_rst_n(manager_video_epoch_rst_n),


        .bank_commit_trig(frame_blank),


        .display_bank(display_bank),


        .bank_switch_commit(),


        .switch_complete_sys(care_switch_complete_sys),


        .bank0_state(bank0_state),


        .bank1_state(bank1_state),


        .bank2_state(bank2_state),


        .bank3_state(bank3_state),


        .bank0_base_addr(),


        .bank1_base_addr(),


        .bank2_base_addr(),


        .bank3_base_addr()


    );





    // 初次上电必须先完成四个Bank的写入，再允许SDRAM读会话启动。


    // 板测显示Bank0干净而Bank1~3有固定花点：Bank0写入时尚无活跃读流，


    // Bank1~3则与Bank0显示读并发。这里把“全部驻留”锁成sys域sticky，


    // 再同步到video域门控首个read_req，消除初装载期读写竞争。


    wire all_banks_resident_sys =


        ((bank0_state == `BANK_STATE_READY) || (bank0_state == `BANK_STATE_DISPLAY)) &&


        ((bank1_state == `BANK_STATE_READY) || (bank1_state == `BANK_STATE_DISPLAY)) &&


        ((bank2_state == `BANK_STATE_READY) || (bank2_state == `BANK_STATE_DISPLAY)) &&


        ((bank3_state == `BANK_STATE_READY) || (bank3_state == `BANK_STATE_DISPLAY));





    always @(posedge clk_100m_sys or negedge media_rst_n) begin


        if (!media_rst_n)


            banks_initialized_sys <= 1'b0;


        else if (all_banks_resident_sys)


            banks_initialized_sys <= 1'b1;


    end





    wire banks_initialized_video;


    cdc_bit_sync u_banks_initialized_sync (


        .clk_dst  (clk_75m),


        .rst_dst  (rst_video),


        .async_in (banks_initialized_sys),


        .sync_out (banks_initialized_video)


    );


    cdc_event_toggle u_recovery_frame_cdc (


        .src_clk(clk_75m),.src_rst(rst_video),


        .src_event(frame_blank && banks_initialized_video),


        .dst_clk(clk_100m_sys),.dst_rst(rst_sys),


        .dst_pulse(recovery_frame_boundary_sys)


    );


    // Local 1 ms clock-enable for media replay and bounded recovery policy.


    always @(posedge clk_100m_sys or posedge rst_sys) begin


        if(rst_sys) begin


            control_tick_count_sys<=0;


            recovery_timeout_tick_sys<=0;


        end else begin


            recovery_timeout_tick_sys<=0;


            if(M9_CONTROL_TICK_CYCLES<=1 ||


               control_tick_count_sys>=M9_CONTROL_TICK_CYCLES*2-1) begin


                control_tick_count_sys<=0;


                recovery_timeout_tick_sys<=1;


            end else begin


                control_tick_count_sys<=control_tick_count_sys+1'b1;


            end


        end


    end





    // 初始化完成可能落在任意扫描行。只在下一次垂直消隐起点放行首个


    // read_req，避免像素0从帧中间开始并永久形成固定的循环纵向偏移。


    reg read_start_enabled_video;


    always @(posedge clk_75m or posedge rst_video) begin


        if (rst_video)


            read_start_enabled_video <= 1'b0;


        else if (frame_blank && banks_initialized_video)


            read_start_enabled_video <= 1'b1;


    end





    // Startup frames can legitimately drain the output FIFO while the first


    // SDRAM read session fills its pipeline. Arm the fatal output-underflow


    // check only from the second enabled frame; later starvation remains fatal.


    reg read_startup_started_video,read_startup_armed_video;


    always @(posedge clk_75m or posedge rst_video) begin


        if (rst_video) begin


            read_startup_started_video <= 1'b0;


            read_startup_armed_video <= 1'b0;


        end else if (!read_start_enabled_video) begin


            read_startup_started_video <= 1'b0;


            read_startup_armed_video <= 1'b0;


        end else if (frame_start) begin


            read_startup_started_video <= 1'b1;


            read_startup_armed_video <= read_startup_started_video;


        end


    end





    // load_complete/load_error 单拍脉冲按 bank 拆分回 frame_manager


    // （loader同一时刻只加载一个bank，load_bank_active标识归属）


    always @(posedge clk_100m_sys or negedge media_rst_n) begin


        if (!media_rst_n) begin


            bank_load_complete <= 4'b0000;


            bank_load_error    <= 4'b0000;


        end else begin


            bank_load_complete <= 4'b0000;


            bank_load_error    <= 4'b0000;


            if (ld_complete) bank_load_complete[load_bank_active] <= 1'b1;


            if (ld_error)    bank_load_error[load_bank_active]    <= 1'b1;


        end


    end





    // =========================================================================


    // 写侧与只读TF/FAT32/BMP媒体链（100 MHz系统域）


    // =========================================================================


    wire        pix_req, pix_rst, pix_valid;


    wire [23:0] pix_rgb888;


    wire        wr_req, wr_en, wr_finish_mem, wr_finish_sys;


    wire        wr_ack;


    wire [31:0] wr_data;


    wire [20:0] wr_addr0, wr_addr1, wr_addr2, wr_addr3, wr_len;


    wire [1:0]  wr_idx;


    wire [7:0]  ld_error_code;





    wire sd_init_busy;


    wire sd_init_done;


    wire sd_init_ready;


    wire [7:0] sd_init_error;


    wire sd_card_high_capacity;


    wire sd_owner_reader;


    wire sd_init_start;


    reg boot_sd_init_start;


    reg sd_init_issued;


    wire media_start;


    reg boot_media_start;


    reg sd_init_failed;


    reg sd_initialized_sys;


    reg [7:0] sd_init_error_latched;


    assign sd_init_start=boot_sd_init_start || recovery_sd_init_start;


    assign media_start=boot_media_start || recovery_media_start;





    wire media_busy;


    wire media_done;


    wire media_error;


    wire [2:0] media_error_stage;


    wire [7:0] media_error_code;


    wire [3:0] media_image_complete;


    wire media_catalog_valid;


    wire [1:0] media_current_image;


    wire media_load_start;


    wire [1:0] media_load_bank;





    wire sd_reader_req;


    wire [31:0] sd_reader_lba;


    wire sd_reader_busy;


    wire sd_reader_done;


    wire sd_reader_valid;


    wire [7:0] sd_reader_byte;


    wire [8:0] sd_reader_byte_index;


    wire [7:0] sd_reader_error;





    // M7-B: one-way SD ownership after all image writes have finished.


    wire image_reader_req,audio_owner,audio_start;


    wire [31:0] image_reader_lba;


    wire [1:0] audio_desired_sys=audio_desired_level_sys[1:0];


    wire [1:0] audio_current_sys;


    wire [3:0] audio_current_level_video;


    wire [1:0] audio_current_video=audio_current_level_video[1:0];


    wire audio_current_update_video;


    reg audio_identity_valid_video;


    wire audio_play_video,audio_education_advance,audio_stream_end;


    wire audio_stream_end_sys,audio_replay_request,audio_replay_accept;


    wire [31:0] audio_played_count;


    wire signed [15:0] monitor_pcm;


    wire monitor_sample_valid,monitor_play_active;


    wire monitor_enable_aligned,monitor_play_active_aligned;


    wire [7:0] monitor_read_addr,monitor_renderer_read_addr,monitor_write_ptr;


    wire [7:0] monitor_write_ptr_aligned;


    wire [8:0] monitor_point_count,monitor_point_count_aligned;


    wire [15:0] monitor_latest_peak,monitor_latest_peak_aligned;


    wire [1:0] monitor_clip_aligned;


    wire [47:0] monitor_read_data,monitor_read_data_aligned;


    wire audio_valid,pre_audio_valid,mixed_audio_valid;


    wire safe_pause_video;


    cdc_bit_sync u_media_pause_sync (


        .clk_dst(clk_75m),.rst_dst(rst_video),


        .async_in(safe_pause_sys),.sync_out(safe_pause_video)


    );


    wire education_play_enable=audio_play_video && !safe_pause_video;


    wire [8:0] pcm_wr_level,pcm_rd_level;


    wire pcm_underflow;


    wire rst_audio_mix;


    qualified_reset_sync u_audio_mix_reset_release (


        .clk(clk_75m),.async_assert(rst_video),.release_async(1'b1),


        .reset_out(rst_audio_mix)


    );


    wire rst_monitor;


    qualified_reset_sync u_monitor_reset_release (


        .clk(clk_75m),.async_assert(rst_video),.release_async(1'b1),


        .reset_out(rst_monitor)


    );


    // Envelope history belongs to the media epoch, not the HDMI timing epoch.


    // Its private reset clears stale points while the renderer and video timing


    // remain alive during local media recovery.


    wire rst_monitor_epoch;


    qualified_reset_sync u_monitor_epoch_reset_release (


        .clk(clk_75m),


        .async_assert(rst_video || media_epoch_reset_sys),


        .release_async(!media_epoch_reset_sys),


        .reset_out(rst_monitor_epoch)


    );


    wire rst_attention;


    qualified_reset_sync u_attention_reset_release (


        .clk(clk_75m),.async_assert(rst_video),.release_async(1'b1),


        .reset_out(rst_attention)


    );


    reg [1:0] audio_current_observed_sys;


    reg audio_current_update_sys;


    always @(posedge clk_100m_sys or posedge rst_media) begin


        if(rst_media) begin


            audio_current_observed_sys<=2'd0;


            audio_current_update_sys<=1'b0;


        end else begin


            audio_current_update_sys<=audio_current_sys!=audio_current_observed_sys;


            if(audio_current_sys!=audio_current_observed_sys)


                audio_current_observed_sys<=audio_current_sys;


        end


    end


    m9_level_cdc u_subtitle_clip (


        .src_clk(clk_100m_sys),.src_rst(rst_media),


        .src_level({2'd0,audio_current_sys}),.src_update(audio_current_update_sys),.src_busy(),


        .dst_clk(clk_75m),.dst_rst(rst_identity_video),.dst_commit(1'b1),


        .dst_level(audio_current_level_video),.dst_update(audio_current_update_video)


    );


    always @(posedge clk_75m or posedge rst_identity_video) begin


        if(rst_identity_video) audio_identity_valid_video<=1'b0;


        else if(audio_current_update_video) audio_identity_valid_video<=1'b1;


    end


    wire audio_catalog_ready,audio_file_error,audio_play_sys,audio_fifo_reset;


    reg audio_fifo_epoch_reset;


    always @(posedge clk_100m_sys or posedge audio_fifo_reset) begin


        if(audio_fifo_reset) audio_fifo_epoch_reset<=1'b1;


        else audio_fifo_epoch_reset<=1'b0;


    end


    wire [3:0] audio_catalog_entries;


    wire [7:0] audio_catalog_scan_error;


    wire [31:0] shared_audio_catalog_size;


    wire [7:0] audio_error_code;


    wire loader_pcm_valid,loader_pcm_ready,loader_pcm_last;


    wire signed [15:0] loader_pcm_data;


    wire shared_audio_file_start,shared_audio_file_reset;


    wire shared_audio_file_busy,shared_audio_file_done,shared_audio_file_valid;


    wire shared_audio_file_ready;


    wire [7:0] shared_audio_file_byte,shared_audio_file_error;


    wire [31:0] shared_audio_file_offset;


    wire wav_pcm_valid,wav_pcm_ready,wav_pcm_last;


    wire signed [15:0] wav_pcm_data;


    m7b_sd_handoff u_audio_handoff (


        .clk(clk_100m_sys),.rst_n(media_rst_n),.images_done(media_done),


        .reader_busy(sd_reader_busy),.reader_valid(sd_reader_valid),


        .reader_done(sd_reader_done),.image_req(image_reader_req),


        .audio_owner(audio_owner),.audio_start(audio_start)


    );


    assign sd_reader_req=image_reader_req;


    assign sd_reader_lba=image_reader_lba;


    cdc_bit_sync u_audio_eof_sys_sync (


        .clk_dst(clk_100m_sys),.rst_dst(rst_sys),


        .async_in(audio_stream_end),.sync_out(audio_stream_end_sys)


    );


    wire audio_replay_request_raw;


    // Suppress a queued request immediately on AUTO ON. On AUTO OFF, mask EOF


    // for one local cycle to re-arm manual replay without changing the PCM epoch.


    assign audio_replay_request=audio_replay_request_raw && !auto_carousel_enable;


    m9_audio_replay_controller #(


        .DELAY_TICKS(M9_AUDIO_REPLAY_DELAY_TICKS)


    ) u_audio_replay (


        .clk(clk_100m_sys),.rst(rst_sys),.timer_tick(recovery_timeout_tick_sys),


        .eof_sync(audio_stream_end_sys && !auto_carousel_previous),.current_bank(audio_current_sys),


        .desired_bank(audio_desired_sys),.key_next(care_replay_cancel || auto_carousel_enable),


        .safe_pause(safe_pause_sys),.media_quiesce(media_quiesce_sys),


        .media_epoch_reset(media_epoch_reset_sys),.audio_error(audio_file_error),


        .replay_accept(audio_replay_accept),.replay_request(audio_replay_request_raw)


    );


    m9_audio_loader u_audio_loader (


        .clk(clk_100m_sys),.rst_n(media_rst_n),.start(audio_start),


        .desired_image(audio_desired_sys),


        .replay_request(audio_replay_request),.replay_accept(audio_replay_accept),


        .shared_catalog_valid(audio_catalog_entries),


        .shared_catalog_error(audio_catalog_scan_error),


        .catalog_file_size(shared_audio_catalog_size),


        .current_image(audio_current_sys),.catalog_valid(audio_catalog_ready),


        .error(audio_file_error),.error_code(audio_error_code),


        .play_enable(audio_play_sys),.fifo_reset(audio_fifo_reset),.file_loaded(),


        .pcm_valid(loader_pcm_valid),.pcm_ready(loader_pcm_ready),


        .pcm_data(loader_pcm_data),.pcm_last(loader_pcm_last),


        .file_start(shared_audio_file_start),.file_reset(shared_audio_file_reset),


        .file_service_busy(shared_audio_file_busy),


        .file_done(shared_audio_file_done),.file_valid(shared_audio_file_valid),


        .file_byte(shared_audio_file_byte),.file_byte_offset(shared_audio_file_offset),


        .file_error(shared_audio_file_error),.file_ready(shared_audio_file_ready)


    );


    m9_pcm_skid_buffer u_pcm_skid (


        .clk(clk_100m_sys),.rst(audio_fifo_reset),.clear(1'b0),


        .in_valid(loader_pcm_valid),.in_ready(loader_pcm_ready),


        .in_data(loader_pcm_data),.in_last(loader_pcm_last),


        .out_valid(wav_pcm_valid),.out_ready(wav_pcm_ready),


        .out_data(wav_pcm_data),.out_last(wav_pcm_last)


    );


`ifdef SIMULATION


    assign wav_pcm_ready=1'b0;


    assign audio_play_video=1'b0;


    assign audio_education_advance=1'b0;


    assign audio_played_count=32'd0;


    assign audio_stream_end=1'b1;


    assign audio_valid=1'b0;


    assign pre_audio_valid=1'b0;


    assign monitor_pcm=16'sd0;


    assign monitor_sample_valid=1'b0;


    assign pcm_wr_level=9'd0;


    assign pcm_rd_level=9'd0;


    assign pcm_underflow=1'b0;


`endif











    always @(posedge clk_100m_sys or negedge media_rst_n) begin


        if (!media_rst_n) begin


            boot_sd_init_start <= 1'b0;


            sd_init_issued <= 1'b0;


            boot_media_start <= 1'b0;


            sd_init_failed <= 1'b0;


            sd_initialized_sys <= 1'b0;


            sd_init_error_latched <= 8'd0;


        end else begin


            boot_sd_init_start <= 1'b0;


            boot_media_start <= 1'b0;


            if(recovery_sd_init_start)


                sd_init_issued <= 1'b1;


            else if(!media_recovery_busy_sys && !sd_init_issued) begin


                sd_init_issued <= 1'b1;


                boot_sd_init_start <= 1'b1;


            end


            if(sd_init_done) begin


                if(sd_init_ready) begin


                    sd_initialized_sys <= 1'b1;


                    if(!media_recovery_busy_sys)


                        boot_media_start <= 1'b1;


                end else begin


                    sd_init_failed <= 1'b1;


                    sd_init_error_latched <= sd_init_error;


                end


            end


        end


    end





    m9_sd_media_service #(


        .INIT_SPI_CLK_DIV(125),          // 100 MHz / (2*125) = 400 kHz


        .READ_SPI_CLK_DIV(2),            // 100 MHz / (2*2) = 25 MHz


        .INIT_STARTUP_DELAY_CYCLES(SD_INIT_STARTUP_CYCLES)


    ) u_sd_media_service (


        .clk(clk_100m_sys), .rst_n(media_rst_n),


        .init_start(sd_init_start), .init_busy(sd_init_busy),


        .init_done(sd_init_done), .init_ready(sd_init_ready),


        .init_error(sd_init_error),


        .card_high_capacity(sd_card_high_capacity), .card_ocr(),


        .owner_reader(sd_owner_reader),


        .sector_req(sd_reader_req), .sector_lba(sd_reader_lba),


        .sector_busy(sd_reader_busy), .sector_done(sd_reader_done),


        .sector_valid(sd_reader_valid), .sector_byte(sd_reader_byte),


        .sector_byte_index(sd_reader_byte_index),


        .sector_error(sd_reader_error),


        .sd_cs_n(sd_ncs), .sd_sclk(sd_dclk), .sd_mosi(sd_mosi),


        .sd_miso(sd_miso)


    );





    // Both credit and BMP request are in the 100 MHz source domain. Leave


    // the loader's in-flight pix_valid untouched; pause only new pixel pulls.


    wire wr_pixel_credit;


    reg wr_pixel_credit_q;


    always @(posedge clk_100m_sys or posedge rst_media) begin


        if(rst_media) wr_pixel_credit_q<=1'b0;


        else wr_pixel_credit_q<=wr_pixel_credit;


    end


    wire [8:0] frame_write_level;


    wire frame_write_ready;


    wire media_pix_req = pix_req && wr_pixel_credit_q;


    m9_media_loader u_media_loader (


        .clk(clk_100m_sys), .rst_n(media_rst_n), .start(media_start),


        .busy(media_busy), .done(media_done), .error(media_error),


        .error_stage(media_error_stage), .error_code(media_error_code),


        .image_complete(media_image_complete),


        .catalog_valid(media_catalog_valid), .current_image(media_current_image),


        .audio_catalog_valid(audio_catalog_entries),


        .audio_catalog_error(audio_catalog_scan_error),


        .catalog_sectors_per_cluster(),.catalog_fat_start_lba(),


        .catalog_data_start_lba(),.catalog_max_cluster(),


        .audio_catalog_index(audio_current_sys),


        .audio_catalog_size(shared_audio_catalog_size),


        .audio_file_enable(audio_owner),.audio_file_start(shared_audio_file_start),


        .audio_file_reset(shared_audio_file_reset),


        .audio_file_busy(shared_audio_file_busy),


        .audio_file_done(shared_audio_file_done),.audio_file_valid(shared_audio_file_valid),


        .audio_file_byte(shared_audio_file_byte),


        .audio_file_byte_offset(shared_audio_file_offset),


        .audio_file_error(shared_audio_file_error),.audio_file_ready(shared_audio_file_ready),


        .reader_req(image_reader_req), .reader_lba(image_reader_lba),


        .reader_busy(sd_reader_busy), .reader_valid(sd_reader_valid),


        .reader_byte(sd_reader_byte),


        .reader_byte_index(sd_reader_byte_index),


        .reader_done(sd_reader_done), .reader_error(sd_reader_error),


        .load_start(media_load_start), .load_bank_index(media_load_bank),


        .load_complete(ld_complete), .load_error(ld_error),


        .load_error_code(ld_error_code), .pix_req(media_pix_req),


        .pix_valid(pix_valid), .pix_rgb888(pix_rgb888)


    );





    m9_media_recovery_manager #(


        .QUIET_CYCLES(32),.RESET_CYCLES(8),.RELEASE_CYCLES(8),


        .RECOVERY_TIMEOUT_CYCLES(M9_MEDIA_RECOVERY_TIMEOUT_CYCLES),


        .TIMER_TICK_CYCLES(M9_CONTROL_TICK_CYCLES*2)


    ) u_media_recovery (


        .clk(clk_100m_sys),.rst(rst_sys),


        .timer_tick(recovery_timeout_tick_sys),


        .recovery_start(recovery_start_sys),


        .reader_request(sd_reader_req),.reader_busy(sd_reader_busy),


        .reader_valid(sd_reader_valid),.reader_done(sd_reader_done),


        .sd_init_done(sd_init_done),.sd_init_ready(sd_init_ready),


        .media_done(media_done),.media_error(media_error),


        .audio_error(audio_file_error),.image_complete(media_image_complete),


        .image_catalog_valid(media_catalog_valid),


        .audio_catalog_valid(audio_catalog_entries),


        .first_frame_confirmed(recovery_frame_boundary_sys),


        .recovery_busy(media_recovery_busy_sys),.media_quiesce(media_quiesce_sys),


        .media_epoch_reset(media_epoch_reset_sys),


        .sd_init_start(recovery_sd_init_start),.media_start(recovery_media_start),


        .recovery_complete(recovery_complete_sys),


        .recovery_failed(recovery_failed_sys),


        .recovery_progress(recovery_progress_sys)


    );


    reg media_system_error_sys;


    reg read_underflow_qualified_video;


    wire read_underflow_sys,pcm_underflow_sys;


    cdc_bit_sync u_media_read_underflow_sync (


        .clk_dst(clk_100m_sys),.rst_dst(rst_media),


        .async_in(read_underflow_qualified_video),.sync_out(read_underflow_sys)


    );


    cdc_bit_sync u_media_pcm_underflow_sync (


        .clk_dst(clk_100m_sys),.rst_dst(rst_media),


        .async_in(pcm_underflow),.sync_out(pcm_underflow_sys)


    );


    wire media_fault_sys=media_system_error_sys || audio_file_error ||


        (banks_initialized_sys && (read_underflow_sys || pcm_underflow_sys));


    always @(posedge clk_100m_sys or negedge media_rst_n) begin


        if (!media_rst_n)


            media_system_error_sys <= 1'b0;


        else if (sd_init_failed || media_error)


            media_system_error_sys <= 1'b1;


    end





    // Only real media faults enter this bounded recovery policy. It has no


    // Health status panel, heartbeat monitoring, or cross-domain recovery bridge.


    m9_failsafe_controller #(


        .RETRY_DELAY_CYCLES(M9_MEDIA_RETRY_DELAY_CYCLES),


        .RECOVERY_TIMEOUT_CYCLES(M9_MEDIA_POLICY_TIMEOUT_CYCLES),


        .TIMER_TICK_CYCLES(M9_CONTROL_TICK_CYCLES*2),


        .MAX_RETRIES(M9_MAX_RECOVERY_RETRIES)


    ) u_media_recovery_policy (


        .clk(clk_100m_sys),.rst(rst_sys),.timer_tick(recovery_timeout_tick_sys),


        .boot_ready(banks_initialized_sys),


        .fault_request(media_fault_sys),.recoverable(1'b1),


        .recovery_complete(recovery_complete_sys),


        .recovery_failed(recovery_failed_sys),


        .recovery_progress(recovery_progress_sys),


        .state(),.retry_count(),


        .safe_pause(safe_pause_sys),.recovery_active(),


        .recovery_start(recovery_start_sys),.clear_sticky()


    );





    // The official writer asserts write_finish for one 125 MHz cycle (8 ns),


    // shorter than a 100 MHz loader cycle (10 ns). A plain 2FF level sampler


    // can miss it entirely, so preserve the event with the M5/M6-A-proven


    // source-toggle crossing before feeding the existing loader.


    cdc_event_toggle u_write_finish_cdc (


        .src_clk(clk_125m_mem), .src_rst(rst_mem),


        .src_event(wr_finish_mem),


        .dst_clk(clk_100m_sys), .dst_rst(rst_sys),


        .dst_pulse(wr_finish_sys)


    );





    // =========================================================================


    // Frame Loader v2（现有双RGB565 word布局和突发间隙保持不变）


    // =========================================================================


    frame_loader_4bank_v2 #(


        .WORDS_PER_FRAME(H_ACT * V_ACT / 2)


    ) u_loader (


        .clk             (clk_100m_sys),


        .rst_n           (media_rst_n),


        .load_bank_index (media_load_bank),


        .load_start      (media_load_start),


        .load_complete   (ld_complete),


        .load_error      (ld_error),


        .error_code      (ld_error_code),


        .load_bank_active(load_bank_active),


        .pix_req         (pix_req),


        .pix_rst         (pix_rst),


        .pix_valid       (pix_valid && media_pix_req),


        .pix_rgb888      (pix_rgb888),


        .write_req       (wr_req),


        .write_req_ack   (wr_ack),


        .write_en        (wr_en),


        .write_data      (wr_data),


        .write_finish    (wr_finish_sys),


        .write_addr_0    (wr_addr0),


        .write_addr_1    (wr_addr1),


        .write_addr_2    (wr_addr2),


        .write_addr_3    (wr_addr3),


        .write_addr_index(wr_idx),


        .write_len       (wr_len)


    );





    // =========================================================================


    // Frame Reader v5（读侧主机，75M = frame service read_clk）


    // 仅在RFIFO真实read_valid时pop；空窗不再把旧dout当成新word。


    // =========================================================================


    wire        rd_req, rd_req_int, rd_pop, rd_finish;


    wire        rd_ack;


    wire [31:0] rd_data;


    wire        rd_valid;


    wire        rd_empty;


    wire [9:0]  rd_level;


    wire        rd_underflow;


    wire        reader_underflow;


    wire        axis_underflow;


    wire [20:0] rd_addr0, rd_addr1, rd_addr2, rd_addr3, rd_len;


    wire [1:0]  rd_idx;





    wire        r_px_valid;


    wire [23:0] r_px_rgb;





    // 显示适配信号（提前声明：u_reader反压、HDMI链与仿真stub共用）


    wire        adt_pause;


    wire        adt_valid;


    wire [23:0] adt_rgb;


    wire        adt_user;


    wire        adt_last;





    // reader自身也只接收初始化完成后的frame_blank，确保调度坐标、Bank锁存和


    // 首个官方read_req从同一个完整视频帧的垂直消隐起点开始。


    assign rd_req = read_start_enabled_video ? rd_req_int : 1'b0;





    frame_reader_4bank_v5_fifo_valid #(


        .WORDS_PER_FRAME(H_ACT * V_ACT / 2)


    ) u_reader (


        .video_clk       (clk_75m),


        .rst_n           (video_rst_n_sync),


        .bank_select     (display_bank),


        .frame_boundary  (frame_blank && banks_initialized_video),


        .de              (de),


        .pixel_x         (pixel_x),


        .read_req        (rd_req_int),


        .read_req_ack    (rd_ack),


        .read_finish     (rd_finish),


        .read_pop        (rd_pop),


        .read_data       (rd_data),


        .read_valid      (rd_valid),


        .read_empty      (rd_empty),


        .read_level      (rd_level),


        .read_addr_0     (rd_addr0),


        .read_addr_1     (rd_addr1),


        .read_addr_2     (rd_addr2),


        .read_addr_3     (rd_addr3),


        .read_addr_index (rd_idx),


        .read_len        (rd_len),


        .out_fifo_pause  (adt_pause),


        .pixel_valid     (r_px_valid),


        .rgb888_out      (r_px_rgb),


        .underflow_sticky(reader_underflow),


        .dbg_pixels_emitted()


    );





    // =========================================================================


    // 显示适配：de对齐像素流 + AXIS视频流打包


    // =========================================================================


    m9_video_axis_source_bram #(


        .PIXELS_PER_FRAME(H_ACT * V_ACT),


        .H_ACT           (H_ACT),


        .FALLBACK_RGB    (24'hFF00FF)


    ) u_adt (


        .video_clk       (clk_75m),


        .rst_n           (!rst_identity_video),


        .frame_start     (frame_start),


        .de              (de),


        .px_valid        (r_px_valid),


        .px_rgb          (r_px_rgb),


        .pixel_valid     (adt_valid),


        .rgb888_out      (adt_rgb),


        .axis_user       (adt_user),


        .axis_last       (adt_last),


        .fifo_pause      (adt_pause),


        .underflow_sticky(axis_underflow),


        .dbg_px_emitted  ()


    );





    // Register the qualification before CDC so the startup underflow deassertion


    // and second-frame arming cannot race through independent synchronizers.


    always @(posedge clk_75m or posedge rst_identity_video) begin


        if (rst_identity_video || !read_startup_armed_video)


            read_underflow_qualified_video <= 1'b0;


        else


            read_underflow_qualified_video <= axis_underflow;


    end





    // =========================================================================


    // 可观测Frame Service + SDRAM硬核封装


    // =========================================================================


    wire        App_wr_en, App_rd_en, Sdr_rd_en, Sdr_init_done;


    wire [20:0] App_wr_addr, App_rd_addr;


    wire [3:0]  App_wr_dm;


    wire [31:0] App_wr_din, Sdr_rd_dout;


    wire        Sdr_init_ref_vld, Sdr_busy;





    // M5/M6-A已验证的自主集成封装：官方frame_fifo_read/write和生成FIFO


    // 保持原样，只把读FIFO配置成show-ahead并公开valid/empty/level。


    // WRITE_PACE_DIV=1保持当前loader的既有写节奏，不引入新的写侧握手要求。


    frame_read_write_rgb565_m9 #(


        .BURST_SIZE     (256),


        .WRITE_V_FLIP   (1),


        .WRITE_PACE_DIV (1),


        .READ_BURST_IDLE_GUARD(1),


        .READ_BURST_REFRESH_BUDGET(1),


        .WRITE_BURST_REFRESH_BUDGET(1),


        .FRAME_WIDTH    (H_ACT / 2),


        .FRAME_HEIGHT   (V_ACT)


    ) u_frame_service (


        .rst             (rst_mem),


        .mem_clk         (clk_125m_mem),


        .Sdr_init_done   (Sdr_init_done),


        .Sdr_init_ref_vld(Sdr_init_ref_vld),


        .Sdr_busy        (Sdr_busy),


        .App_rd_en       (App_rd_en),


        .App_rd_addr     (App_rd_addr),


        .Sdr_rd_en       (Sdr_rd_en),


        .Sdr_rd_dout     (Sdr_rd_dout),


        .read_clk        (clk_75m),


        .read_req        (rd_req),


        .read_req_ack    (rd_ack),


        .read_finish     (rd_finish),


        .read_addr_0     (rd_addr0),


        .read_addr_1     (rd_addr1),


        .read_addr_2     (rd_addr2),


        .read_addr_3     (rd_addr3),


        .read_addr_index (rd_idx),


        .read_len        (rd_len),


        .read_pop        (rd_pop),


        .read_data       (rd_data),


        .read_valid      (rd_valid),


        .read_empty      (rd_empty),


        .read_level      (rd_level),


        .clear_read_faults(1'b0),


        .read_underflow_sticky(rd_underflow),


        .App_wr_en       (App_wr_en),


        .App_wr_addr     (App_wr_addr),


        .App_wr_din      (App_wr_din),


        .App_wr_dm       (App_wr_dm),


        .write_clk       (clk_100m_sys),


        .write_req       (wr_req),


        .write_req_ack   (wr_ack),


        .write_finish    (wr_finish_mem),


        .write_addr_0    (wr_addr0),


        .write_addr_1    (wr_addr1),


        .write_addr_2    (wr_addr2),


        .write_addr_3    (wr_addr3),


        .write_addr_index(wr_idx),


        .write_len       (wr_len),


        .write_en        (wr_en),


        .write_data      (wr_data),


        .write_ready     (frame_write_ready),


        .write_full      (),


        .write_pixel_credit(wr_pixel_credit),


        .write_level     (frame_write_level)


    );





    // SDRAM封装：模块名固定为sdram，按构建选择源文件——


    //   综合: rtl/memory/official/sdram.v（内部例化EG_PHY_SDRAM_2M_32硬核）


    //   仿真: rtl/memory/sdram_app_sim.v（行为级替身，sdr_as_ram加密不可仿真）


    // Address-only wipe: original reader, whole-burst enable and FIFO unchanged.


    wire [20:0] mapped_rd_addr;


    wire [1:0] wipe_image_mem;


    wire [3:0] wipe_image_level_video;


    wire [1:0] wipe_image_video=wipe_image_level_video[1:0];


    wire wipe_status_event,wipe_image_update_video;


    reg wipe_identity_valid_video;


    m6e_wipe_read_address #(


        .FRAME_WORDS(H_ACT * V_ACT / 2), .STEP_WORDS(H_ACT * 24 / 2)


    ) u_wipe (


        .mem_clk(clk_125m_mem), .rst(rst_mem), .read_ack(rd_ack),


        .app_en(App_rd_en), .app_addr(App_rd_addr),


        .mapped_addr(mapped_rd_addr), .image_bank(wipe_image_mem),


        .status_event(wipe_status_event)


    );


    // Absolute target identity is resent after either side resets. IMAGE still


    // identifies the captured incoming wipe target, never a queued request.


    m9_level_cdc u_wipe_status (


        .src_clk(clk_125m_mem),.src_rst(rst_mem),


        .src_level({2'd0,wipe_image_mem}),.src_update(wipe_status_event),.src_busy(),


        .dst_clk(clk_75m),.dst_rst(rst_identity_video),.dst_commit(1'b1),


        .dst_level(wipe_image_level_video),.dst_update(wipe_image_update_video)


    );


    always @(posedge clk_75m or posedge rst_identity_video) begin


        if(rst_identity_video) wipe_identity_valid_video<=1'b0;


        else if(wipe_image_update_video) wipe_identity_valid_video<=1'b1;


    end


    reg [1:0] product_theme_video;


    always @(posedge clk_75m or posedge rst_manager_video_epoch) begin


        if(rst_manager_video_epoch) product_theme_video<=2'd0;


        else if(wipe_image_update_video) product_theme_video<=wipe_image_video;


    end





    // Do not export the destination reset default. The audio-selection source


    // remains reset until an authoritative wipe identity has been received.


    wire rst_audio_select_video=rst_identity_video || !wipe_identity_valid_video;


    wire hdmi_axis_valid,hdmi_axis_user,hdmi_axis_last;


    wire [3:0] care_page_status_video;


    wire care_page_update_video;


    m9_care_page_status u_care_page_status (


        .clk(clk_75m),.rst(rst_identity_video),


        .frame_start(hdmi_axis_valid && hdmi_axis_user),


        .page_valid(wipe_identity_valid_video),.page_id(wipe_image_video),


        .audio_identity_valid(audio_identity_valid_video),.audio_id(audio_current_video),


        .audio_play(audio_play_video),.education_advance(audio_education_advance),


        .played_count(audio_played_count),.stream_end(audio_stream_end),


        .status(care_page_status_video),.status_update(care_page_update_video)


    );


    m9_level_cdc u_audio_select (


        .src_clk(clk_75m),.src_rst(rst_audio_select_video),


        .src_level(care_page_status_video),.src_update(care_page_update_video),.src_busy(),


        .dst_clk(clk_100m_sys),.dst_rst(rst_media),.dst_commit(1'b1),


        .dst_level(audio_desired_level_sys),.dst_update()


    );





    sdram u_sdram (


        .Clk            (clk_125m_mem),


        .Clk_sft        (clk_125m_mem_sft),


        .Rst            (rst_mem),


        .Sdr_init_done  (Sdr_init_done),


        .Sdr_init_ref_vld(Sdr_init_ref_vld),


        .Sdr_busy       (Sdr_busy),


        .App_wr_en      (App_wr_en),


        .App_wr_addr    (App_wr_addr),


        .App_wr_dm      (App_wr_dm),


        .App_wr_din     (App_wr_din),


        .App_rd_en      (App_rd_en),


        .App_rd_addr    (mapped_rd_addr),


        .Sdr_rd_en      (Sdr_rd_en),


        .Sdr_rd_dout    (Sdr_rd_dout)


    );





    // =========================================================================


    // M6-A亮度链与安全状态画面


    // =========================================================================


    wire media_error_video;


    cdc_bit_sync u_media_error_sync (


        .clk_dst(clk_75m), .rst_dst(rst_video),


        .async_in(media_system_error_sys), .sync_out(media_error_video)


    );





    wire brightness_event_video;


    cdc_event_toggle u_brightness_event_cdc (


        .src_clk(clk_100m_sys), .src_rst(rst_sys),


        .src_event(brightness_event_sys),


        .dst_clk(clk_75m), .dst_rst(rst_video),


        .dst_pulse(brightness_event_video)


    );





    wire [3:0] brightness_level;


    wire brightness_update_video;


    m9_level_cdc u_brightness_level_cdc(


        .src_clk(clk_100m_sys),.src_rst(rst_sys),


        .src_level(brightness_level_sys),.src_update(brightness_update_sys),.src_busy(),


        .dst_clk(clk_75m),.dst_rst(rst_video),.dst_commit(frame_start),


        .dst_level(brightness_level),.dst_update(brightness_update_video));





    // Keep HDMI timing alive during initialization or failure. Partial banks are


    // never shown: loading is blue, a latched media error is red.


    wire [23:0] media_or_status_rgb = media_error_video ? 24'h800000 :


                                      (!banks_initialized_video ? 24'h204080 : adt_rgb);


    wire monitor_axis_valid,monitor_axis_user,monitor_axis_last;


    wire [14:0] monitor_axis_x,monitor_axis_y;


    wire [23:0] monitor_axis_rgb;


    wire attention_axis_valid,attention_axis_user,attention_axis_last;


    wire [14:0] attention_axis_x,attention_axis_y;


    wire [23:0] attention_axis_rgb;


    wire [14:0] hdmi_axis_x,hdmi_axis_y;


    wire [23:0] hdmi_input_rgb;


    wire display_valid,display_user,display_last,display_subtitle_first;


    wire [14:0] display_x,display_y;


    wire [23:0] display_rgb;


    wire subtitle_axis_valid,subtitle_axis_user,subtitle_axis_last;


    wire [14:0] subtitle_axis_x,subtitle_axis_y;


    wire [23:0] subtitle_axis_rgb;


    wire subtitle_active,subtitle_valid;


    wire [7:0] subtitle_index,subtitle_text;


    wire [1:0] subtitle_style;


    wire [3:0] subtitle_progress;


    wire [6:0] subtitle_u6_glyph_id,attention_u6_glyph_id;


    wire [3:0] subtitle_u6_glyph_row,attention_u6_glyph_row;


    wire [15:0] subtitle_u6_glyph_bits,attention_u6_glyph_bits;


    wire subtitle_clear=!wipe_identity_valid_video || !audio_identity_valid_video ||


                        audio_stream_end || audio_played_count==0 || !audio_play_video ||


                        audio_current_video!=wipe_image_video;


    m9_product_subtitle_timeline u_subtitle_timeline (


        .clk(clk_75m),.rst(rst_video),.clip_ready(audio_play_video),


        .clip_id(audio_current_video),.epoch_clear(subtitle_clear),


        .education_advance(audio_education_advance),.played_sample_count(audio_played_count),


        .content_active(subtitle_active),.cue_valid(subtitle_valid),.cue_index(subtitle_index),


        .text_id(subtitle_text),.style_id(subtitle_style),.progress_step(subtitle_progress)


    );


    m9_u6_glyph_rom u_u6_glyph_rom (


        .clk(clk_75m),.subtitle_glyph_id(subtitle_u6_glyph_id),


        .subtitle_row(subtitle_u6_glyph_row),.subtitle_bits(subtitle_u6_glyph_bits),


        .attention_glyph_id(attention_u6_glyph_id),


        .attention_row(attention_u6_glyph_row),.attention_bits(attention_u6_glyph_bits)


    );


    m9_product_subtitle_renderer u_subtitle_overlay (


        .clk(clk_75m),.rst(rst_video),.diagnostic_pending(1'b0),.in_valid(display_valid),.in_user(display_user),


        .in_last(display_last),.in_x(display_x),.in_y(display_y),.in_rgb(display_rgb),


        .clear_pending(subtitle_clear || media_error_video || !banks_initialized_video),


        .active_pending(subtitle_active),.cue_valid_pending(subtitle_valid),


        .cue_index_pending(subtitle_index),.text_id_pending(subtitle_text),


        .style_pending(subtitle_style),


        .progress_pending(subtitle_progress),.in_pending_first(display_subtitle_first),


        .u6_glyph_id(subtitle_u6_glyph_id),.u6_glyph_row(subtitle_u6_glyph_row),


        .u6_glyph_bits(subtitle_u6_glyph_bits),


        .out_valid(subtitle_axis_valid),


        .out_user(subtitle_axis_user),.out_last(subtitle_axis_last),


        .out_x(subtitle_axis_x),.out_y(subtitle_axis_y),.out_rgb(subtitle_axis_rgb)


    );


    m9_audio_monitor_phase_adapter u_monitor_phase (


        .clk(clk_75m),.rst_state(rst_monitor),.rst_epoch(rst_monitor_epoch),


        .early_valid(display_valid),.early_user(display_user),.early_x(display_x),


        .monitor_enable_pending(banks_initialized_video && read_start_enabled_video &&


                                wipe_identity_valid_video && audio_identity_valid_video),


        .write_ptr_pending(monitor_write_ptr),.point_count_pending(monitor_point_count),


        .latest_peak_pending(monitor_latest_peak),.clip_id_pending(audio_current_video),


        .play_active_pending(monitor_play_active && audio_identity_valid_video),.envelope_read_data(monitor_read_data),


        .envelope_read_addr(monitor_read_addr),


        .monitor_enable_aligned(monitor_enable_aligned),


        .write_ptr_aligned(monitor_write_ptr_aligned),


        .point_count_aligned(monitor_point_count_aligned),


        .latest_peak_aligned(monitor_latest_peak_aligned),


        .clip_id_aligned(monitor_clip_aligned),


        .play_active_aligned(monitor_play_active_aligned),


        .envelope_read_data_aligned(monitor_read_data_aligned)


    );


    m7d_audio_envelope u_audio_envelope (


        .clk(clk_75m),.rst(rst_monitor_epoch),.sample_valid(monitor_sample_valid),


        .sample_pcm(monitor_pcm),.read_addr(monitor_read_addr),.read_data(monitor_read_data),


        .write_ptr(monitor_write_ptr),.point_count(monitor_point_count),


        .point_commit(),.latest_peak(monitor_latest_peak)


    );


    m9_audio_monitor_renderer u_audio_monitor (


        .clk(clk_75m),.rst(rst_monitor),.in_valid(subtitle_axis_valid),


        .in_user(subtitle_axis_user),.in_last(subtitle_axis_last),


        .in_x(subtitle_axis_x),.in_y(subtitle_axis_y),.in_rgb(subtitle_axis_rgb),


        .monitor_enable(monitor_enable_aligned),


        .write_ptr_pending(monitor_write_ptr_aligned),


        .point_count_pending(monitor_point_count_aligned),


        .latest_peak_pending(monitor_latest_peak_aligned),


        .clip_id_pending(monitor_clip_aligned),


        .play_active_pending(monitor_play_active_aligned),


        .envelope_read_addr(monitor_renderer_read_addr),


        .envelope_read_data(monitor_read_data_aligned),.out_valid(monitor_axis_valid),


        .out_user(monitor_axis_user),.out_last(monitor_axis_last),


        .out_x(monitor_axis_x),.out_y(monitor_axis_y),.out_rgb(monitor_axis_rgb)


    );





    // M8-C retains the final video layer and consumes the same event in audio.


    // Only real education consumption advances the unchanged subtitle timeline.


    wire m8_source_update,m8_source_active,m8_source_busy,m8_source_ack;


    wire [1:0] m8_source_level;


    wire [7:0] m8_source_event_id,m8_source_epoch;


    wire m8_video_apply,m8_video_active /* synthesis dont_touch = true */;


    wire [1:0] m8_video_level /* synthesis dont_touch = true */;


    wire [7:0] m8_video_event_id,m8_video_epoch /* synthesis dont_touch = true */;


    wire m8_audio_apply,m8_audio_active /* synthesis dont_touch = true */;


    wire [1:0] m8_audio_level /* synthesis dont_touch = true */;


    wire [7:0] m8_audio_event_id,m8_audio_epoch /* synthesis dont_touch = true */;


    assign monitor_play_active=(education_play_enable && !audio_stream_end) ||


        (m8_audio_active && (m8_audio_level==2'd1 || m8_audio_level==2'd2) && monitor_latest_peak!=0);


    m8_mode_switches #(


        .STABLE_CYCLES(M8_SWITCH_STABLE_CYCLES)


    ) u_m8_switches (


        .clk(clk_100m_sys),.rst(rst_sys),


        .sw_warning_async(sw_warning),.sw_emergency_async(sw_emergency),


        .event_update(m8_source_update),.event_active(m8_source_active),


        .event_level(m8_source_level),.event_id(m8_source_event_id),


        .event_epoch(m8_source_epoch)


    );


    m8_event_dual_commit u_m8_event_commit (


        .src_clk(clk_100m_sys),.src_rst(rst_sys),.src_update(m8_source_update),


        .src_event_active(m8_source_active),.src_level(m8_source_level),


        .src_event_id(m8_source_event_id),.src_epoch(m8_source_epoch),


        .src_busy(m8_source_busy),.src_ack_pulse(m8_source_ack),


        .dst_clk(clk_75m),.dst_rst(rst_video),


        .video_boundary(display_valid && display_user),


        .audio_boundary(pre_audio_valid),


        .video_apply_pulse(m8_video_apply),.video_event_active(m8_video_active),


        .video_level(m8_video_level),.video_event_id(m8_video_event_id),


        .video_epoch(m8_video_epoch),


        .audio_apply_pulse(m8_audio_apply),.audio_event_active(m8_audio_active),


        .audio_level(m8_audio_level),.audio_event_id(m8_audio_event_id),


        .audio_epoch(m8_audio_epoch)


    );


    // Attention's packet moves two clocks later; retain the event values sampled


    // at the frozen-D1 absolute edge without valid gating or frame re-sampling.


    reg m8_video_active_d1,m8_video_active_d2;


    reg [1:0] m8_video_level_d1,m8_video_level_d2;


    reg [7:0] m8_video_event_id_d1,m8_video_event_id_d2;


    reg [7:0] m8_video_epoch_d1,m8_video_epoch_d2;


    always @(posedge clk_75m or posedge rst_attention) begin


        if(rst_attention) begin


            m8_video_active_d1<=0;m8_video_active_d2<=0;


            m8_video_level_d1<=0;m8_video_level_d2<=0;


            m8_video_event_id_d1<=0;m8_video_event_id_d2<=0;


            m8_video_epoch_d1<=0;m8_video_epoch_d2<=0;


        end else begin


            m8_video_active_d1<=m8_video_active;m8_video_active_d2<=m8_video_active_d1;


            m8_video_level_d1<=m8_video_level;m8_video_level_d2<=m8_video_level_d1;


            m8_video_event_id_d1<=m8_video_event_id;m8_video_event_id_d2<=m8_video_event_id_d1;


            m8_video_epoch_d1<=m8_video_epoch;m8_video_epoch_d2<=m8_video_epoch_d1;


        end


    end


    m9_product_attention_renderer u_m8_attention (


        .clk(clk_75m),.rst(rst_attention),


        .in_valid(monitor_axis_valid),.in_user(monitor_axis_user),


        .in_last(monitor_axis_last),.in_x(monitor_axis_x),.in_y(monitor_axis_y),


        .in_rgb(monitor_axis_rgb),.event_active_pending(m8_video_active_d2),


        .event_level_pending(m8_video_level_d2),.event_id_pending(m8_video_event_id_d2),


        .event_epoch_pending(m8_video_epoch_d2),


        .u6_glyph_id(attention_u6_glyph_id),.u6_glyph_row(attention_u6_glyph_row),


        .u6_glyph_bits(attention_u6_glyph_bits),.out_valid(attention_axis_valid),


        .out_user(attention_axis_user),.out_last(attention_axis_last),


        .out_x(attention_axis_x),.out_y(attention_axis_y),.out_rgb(attention_axis_rgb)


    );


    wire [7:0] monitor_hr_bpm,monitor_spo2_percent,monitor_rr_bpm;


    wire monitor_hr_valid,monitor_spo2_valid,monitor_rr_valid,monitor_update;


    wire [1:0] monitor_data_source;


    wire [11:0] monitor_hr_bcd,monitor_spo2_bcd,monitor_rr_bcd;


    wire vital_sensor_ready;


    wire [7:0] vital_sensor_fault;


    m9_vital_processing_subsystem u_vital_processing (


        .sys_clk(clk_100m_sys),.sys_rst(rst_sys),.video_clk(clk_75m),.video_rst(rst_video),


        .vital_i2c_scl(vital_i2c_scl),.vital_i2c_sda(vital_i2c_sda),


        .hr_bpm(monitor_hr_bpm),.spo2_percent(monitor_spo2_percent),.rr_bpm(monitor_rr_bpm),


        .hr_valid(monitor_hr_valid),.spo2_valid(monitor_spo2_valid),.rr_valid(monitor_rr_valid),


        .data_source(monitor_data_source),.monitor_update(monitor_update),


        .hr_bcd(monitor_hr_bcd),.spo2_bcd(monitor_spo2_bcd),.rr_bcd(monitor_rr_bcd),


        .sensor_ready(vital_sensor_ready),.sensor_fault(vital_sensor_fault)


    );


    m9_vital_monitor_overlay u_vital_monitor_overlay (


        .clk(clk_75m),.rst(rst_video),


        .in_valid(attention_axis_valid),.in_user(attention_axis_user),


        .in_last(attention_axis_last),.in_x(attention_axis_x),.in_y(attention_axis_y),


        .in_rgb(attention_axis_rgb),.diagnostic_pending(1'b0),


        .alert_active_pending(m8_video_active_d2),.monitor_update(monitor_update),


        .hr_bpm(monitor_hr_bpm),.spo2_percent(monitor_spo2_percent),


        .rr_bpm(monitor_rr_bpm),.hr_valid(monitor_hr_valid),


        .spo2_valid(monitor_spo2_valid),.rr_valid(monitor_rr_valid),


        .data_source(monitor_data_source),.hr_bcd(monitor_hr_bcd),


        .spo2_bcd(monitor_spo2_bcd),.rr_bcd(monitor_rr_bcd),


        .brightness_level_pending(brightness_level),.brightness_update(brightness_update_video),


        .out_valid(hdmi_axis_valid),


        .out_user(hdmi_axis_user),.out_last(hdmi_axis_last),


        .out_x(hdmi_axis_x),.out_y(hdmi_axis_y),


        .out_rgb(hdmi_input_rgb)


    );


    wire [3:0] volume_level;


    wire volume_update_video;


`ifdef SIMULATION


    assign volume_level=volume_level_sys;


    assign volume_update_video=volume_update_sys;


`endif


    // Display backend only: raw coordinates are delayed to the registered


    // AXIS packet, then brightness and OSD share a three-stage output pipeline.


    m9_product_video_pipeline #(.ENABLE_VOLUME_OSD(1)) u_display (


        .clk(clk_75m), .rst(rst_video),


        .raw_x(pixel_x), .raw_y(pixel_y),


        .in_valid(adt_valid), .in_user(adt_user), .in_last(adt_last),


        .in_rgb(media_or_status_rgb), .theme_pending(product_theme_video),


        .level_pending(brightness_level), .offset_pending(9'sd0),


        .brightness_event_pending(brightness_event_video),


        .volume_event_pending(volume_update_video),.volume_level_pending(volume_level),


        .ready_pending(banks_initialized_video && read_start_enabled_video &&


                       wipe_identity_valid_video), .error_pending(media_error_video),


        .out_valid(display_valid), .out_user(display_user),


        .out_last(display_last), .out_x(display_x), .out_y(display_y), .out_rgb(display_rgb),


        .out_subtitle_first(display_subtitle_first)


    );





`ifndef SIMULATION


    // =========================================================================


    // HDMI Output Chain（搬自已板测的 top_m6a_720p_osd，HDMI_B接口）


    // =========================================================================


    wire audio_i2s_bclk, audio_i2s_lrck, audio_i2s_dout;


    wire [23:0] audio_left_data, audio_right_data;


    wire [23:0] pre_audio_left,pre_audio_right,mixed_audio_left,mixed_audio_right;


    wire acr_valid;


    wire [19:0] acr_cts;


    wire [19:0] acr_n;


    wire edid_trig;


    wire [9:0]  tmds_ch0_data, tmds_ch1_data, tmds_ch2_data, tmds_clk_data;





    wire audio_tick;


    wire [23:0] diagnostic_left,diagnostic_right,wav_left,wav_right;


    cdc_bit_sync u_audio_enable_sync (


        .clk_dst(clk_75m),.rst_dst(rst_video),


        .async_in(audio_play_sys),.sync_out(audio_play_video)


    );


    m7a_pcm_playback u_pcm_player (


        .wr_clk(clk_100m_sys),.rd_clk(clk_75m),.rst(audio_fifo_epoch_reset),


        .pcm_valid(wav_pcm_valid),.pcm_ready(wav_pcm_ready),.pcm_data(wav_pcm_data),.pcm_last(wav_pcm_last),


        .sample_tick(audio_tick),.play_enable(education_play_enable),.audio_valid(),


        .audio_left(wav_left),.audio_right(wav_right),.played_pcm(),


        .education_advance(audio_education_advance),.played_sample_count(audio_played_count),.stream_end(audio_stream_end),


        .underflow_sticky(pcm_underflow),.wr_level(pcm_wr_level),.rd_level(pcm_rd_level)


    );


    m7b_audio_boundary u_audio_boundary (


        .clk(clk_75m),.rst(rst_video),.sample_tick(audio_tick),.use_wav(audio_play_video),


        .tone_left(diagnostic_left),.tone_right(diagnostic_right),


        .wav_left(wav_left),.wav_right(wav_right),


        .audio_valid(pre_audio_valid),.audio_left(pre_audio_left),.audio_right(pre_audio_right)


    );


    m8_audio_output u_m8_audio (


        .clk(clk_75m),.rst(rst_audio_mix),.pre_valid(pre_audio_valid),


        .pre_left(pre_audio_left),.pre_right(pre_audio_right),


        .event_active(m8_audio_active),.event_level(m8_audio_level),


        .event_id(m8_audio_event_id),.event_epoch(m8_audio_epoch),


        .out_valid(mixed_audio_valid),.out_left(mixed_audio_left),


        .out_right(mixed_audio_right)


    );


    wire scaled_audio_valid;


    wire [23:0] scaled_audio_left,scaled_audio_right;


    m9_level_cdc u_volume_level_cdc(


        .src_clk(clk_100m_sys),.src_rst(rst_sys),


        .src_level(volume_level_sys),.src_update(volume_update_sys),.src_busy(),


        .dst_clk(clk_75m),.dst_rst(rst_audio_mix),.dst_commit(mixed_audio_valid),


        .dst_level(volume_level),.dst_update(volume_update_video));


    // Actual final-mix PCM gain; the SAFE gate and Audio Monitor both consume


    // this same scaled stream. Sample-valid count and education timing are unchanged.


    m9_pcm_volume u_final_volume(


        .clk(clk_75m),.rst(rst_audio_mix),.in_valid(mixed_audio_valid),


        .in_left(mixed_audio_left),.in_right(mixed_audio_right),


        .level(volume_level),.level_update(volume_update_video),


        .out_valid(scaled_audio_valid),.out_left(scaled_audio_left),.out_right(scaled_audio_right));


    m9_audio_safe_gate u_audio_safe_gate (


        .clk(clk_75m),.rst(rst_audio_mix),.in_valid(scaled_audio_valid),


        .in_left(scaled_audio_left),.in_right(scaled_audio_right),


        .safe_pause(safe_pause_video),.out_valid(audio_valid),


        .out_left(audio_left_data),.out_right(audio_right_data)


    );


    assign monitor_pcm=$signed(audio_left_data[23:8]);


    assign monitor_sample_valid=audio_valid;





    hdmi_audio_tone_i2s_64fs #(


        .PHASE_INC(32'd39370534),


        // VOL001 is a quiet audible test level: 40,000 is 34 dB below the


        // previously validated 2,000,000 amplitude. One PCM LSB proved silent.


        .AMP      (24'sd40000)


    ) u_audio_tone (


        .I_mclk    (clk_audio_mclk),


        .I_rst     (rst_audio),


        .O_i2s_BCLK(audio_i2s_bclk),


        .O_i2s_LRCK(audio_i2s_lrck),


        .O_i2s_DOUT(audio_i2s_dout)


    );





    i2s_receiver_hardened u_i2s_receiver (


        .I_clk        (clk_75m),


        .I_rst        (rst_video),


        .I_i2s_BCLK   (audio_i2s_bclk),


        .I_i2s_LRCK   (audio_i2s_lrck),


        .I_i2s_DOUT   (audio_i2s_dout),


        .O_audio_valid(audio_tick),


        .O_audio_left_data (diagnostic_left),


        .O_audio_right_data(diagnostic_right)


    );





    audio_arc_calculate #(


        .ACR_N(6144)


    ) u_audio_arc_calculate (


        .I_clk       (clk_75m),


        .I_rst       (rst_video),


        .I_audio_valid(audio_valid),


        .O_acr_valid (acr_valid),


        .O_acr_cts   (acr_cts),


        .O_acr_n     (acr_n)


    );





    startup_pulse #(


        .CNT_MAX(20'd300000)


    ) u_startup_pulse (


        .I_clk  (clk_75m),


        .I_rst  (rst_video),


        .O_pulse(edid_trig)


    );





    hdmi_1_4b_transmitter_core_wrapper #(


        .DEVICE           ("EG"),


        .HTOTAL           (H_ACT + H_FP + H_SYNC + H_BP),


        .HSA              (H_SYNC),


        .HFP              (H_FP),


        .HBP              (H_BP),


        .HACTIVE          (H_ACT),


        .VTOTAL           (V_ACT + V_FP + V_SYNC + V_BP),


        .VSA              (V_SYNC),


        .VFP              (V_FP),


        .VBP              (V_BP),


        .VACTIVE          (V_ACT),


        .VIDEO_VIC        (4),              // CEA-861: 720p60


        .VIDEO_TPG        ("Disable"),      // 图案来自本设计的SDRAM显示流


        .VIDEO_FORMAT     ("RGB"),


        .AUDIO_SAMPLE_RATE("48K"),


        .IIC_SCL_DIV      (125)


    ) u_hdmi_core (


        .I_pixel_clk     (clk_75m),


        .I_rst           (rst_hdmi),


        .I_edid_read_trig(edid_trig),


        .O_edid_read_valid(),


        .O_edid_read_data(),


        .I_axis_s_user   (hdmi_axis_user),


        .I_axis_s_valid  (hdmi_axis_valid),


        .I_axis_s_last   (hdmi_axis_last),


        .I_axis_s_data   (hdmi_input_rgb),


        .O_axis_s_ready  (),


        .I_audio_valid   (audio_valid),


        .I_audio_left_data (audio_left_data),


        .I_audio_right_data(audio_right_data),


        .I_acr_valid     (acr_valid),


        .I_acr_cts       (acr_cts),


        .I_acr_n         (acr_n),


        .O_video_locked  (),


        .O_ddc_scl       (HDMI_DDC_SCL),


        .IO_ddc_sda      (HDMI_DDC_SDA),


        .O_ch0_tmds_data (tmds_ch0_data),


        .O_ch1_tmds_data (tmds_ch1_data),


        .O_ch2_tmds_data (tmds_ch2_data),


        .O_clk_tmds_data (tmds_clk_data)


    );





    hdmi_phy_wrapper_hardened #(


        .DEVICE("EG")


    ) u_hdmi_phy (


        .I_pixel_clk  (clk_75m),


        .I_serial_clk (clk_375m_hdmi),


        .I_pixel_rst  (rst_hdmi),


        .I_serial_rst (rst_hdmi_serial),


        .I_tmds_channel_0   (tmds_ch0_data),


        .I_tmds_channel_1   (tmds_ch1_data),


        .I_tmds_channel_2   (tmds_ch2_data),


        .I_tmds_channel_clk (tmds_clk_data),


        .O_tmds_ch0_p (HDMI_D0_P),


        .O_tmds_ch1_p (HDMI_D1_P),


        .O_tmds_ch2_p (HDMI_D2_P),


        .O_tmds_clk_p (HDMI_CLK_P)


    );


`endif








    // =========================================================================


    // Debug: 7-Segment Display (michu seg7_panel: PIC/VOL/PRD pages)


    // =========================================================================


    // display_bank是video_clk域寄存器（frame_manager视频域提交），进sys_clk域


    // 的seg7译码前必须同步（2026-09-19 STA报告暴露的裸跨域，CDC登记表补充）。


    // bank编号为准静态电平：3拍同步器（2FF同步+1拍参考），边沿在sys域本地


    // 生成pic_event（原bank_switch_commit为video域单拍脉冲，跨域必然丢失）。


    reg [1:0] disp_bank_sync1, disp_bank_sync2, disp_bank_sync3;


    always @(posedge clk_100m_sys or negedge sys_rst_n_sync) begin


        if (!sys_rst_n_sync) begin


            disp_bank_sync1 <= 2'd0;


            disp_bank_sync2 <= 2'd0;


            disp_bank_sync3 <= 2'd0;


        end else begin


            disp_bank_sync1 <= display_bank;


            disp_bank_sync2 <= disp_bank_sync1;


            disp_bank_sync3 <= disp_bank_sync2;


        end


    end


    wire pic_event_sys = (disp_bank_sync2 != disp_bank_sync3);





    // PIC页显示当前显示Bank编号(1-4)，bank切换事件强制PIC页2秒


    wire [5:0] seg7_anode_panel;           // SEL2..SEL7，物理从左到右六位


    wire [7:0] seg7_seg_panel;             // 面板段码





    seg7_panel #(


        .CLK_HZ(100000000)


    ) u_seg7 (


        .clk       (clk_100m_sys),


        .rst_n     (sys_rst_n_sync),


        .enable    (1'b1),


        .media_id  (disp_bank_sync2),


        .volume    ({4'd0, volume_level_sys}),


        .period_sec(6'd10),


        .pic_event (pic_event_sys),


        .vol_event (volume_update_sys),


        .prd_event (1'b0),


        .seg_n     (seg7_seg_panel),


        .dig_n     (seg7_anode_panel)


    );





    wire [5:0] error_seg7_anode;


    wire [7:0] error_seg7_cathode;


    wire [2:0] display_error_stage = sd_init_failed ? 3'd5 : media_error_stage;


    wire [7:0] display_error_code =


        sd_init_failed ? sd_init_error_latched : media_error_code;


    m6c_error_seg7 u_error_seg7 (


        .clk(clk_100m_sys), .rst_n(sys_rst_n_sync),


        .active(media_system_error_sys),


        .error_stage(display_error_stage), .error_code(display_error_code),


        .seg_n(error_seg7_cathode), .dig_n(error_seg7_anode)


    );





    wire [7:0] m8_seg7_cathode;


    m8_event_debug_indicator u_m8_event_debug (


        .video_apply(m8_video_apply),.video_active(m8_video_active),


        .video_level(m8_video_level),.video_event_id(m8_video_event_id),


        .video_epoch(m8_video_epoch),.audio_apply(m8_audio_apply),


        .audio_active(m8_audio_active),.audio_level(m8_audio_level),


        .audio_event_id(m8_audio_event_id),.audio_epoch(m8_audio_epoch),


        .panel_seg_n(seg7_seg_panel),.media_error(media_system_error_sys),


        .error_seg_n(error_seg7_cathode),.seg_n(m8_seg7_cathode)


    );


    // Startup diagnostic candidate only: observe, never drive functional reset/control.


    reg [9:0] diag_sys_count,diag_mem_count,diag_video_count;


    reg [15:0] diag_serial_count;


    reg diag_frame_toggle;


    always @(posedge clk_100m_sys or negedge sys_rst_n)


        if(!sys_rst_n) diag_sys_count<=0;else diag_sys_count<=diag_sys_count+1'b1;


    always @(posedge clk_125m_mem or negedge sys_rst_n)


        if(!sys_rst_n) diag_mem_count<=0;else diag_mem_count<=diag_mem_count+1'b1;


    always @(posedge clk_75m or negedge sys_rst_n)


        if(!sys_rst_n) diag_video_count<=0;else diag_video_count<=diag_video_count+1'b1;


    always @(posedge clk_375m_hdmi or negedge sys_rst_n)


        if(!sys_rst_n) diag_serial_count<=0;


        else diag_serial_count<={diag_serial_count[14:0],!diag_serial_count[15]};


    always @(posedge clk_75m or negedge sys_rst_n)


        if(!sys_rst_n) diag_frame_toggle<=0;


        else if(hdmi_axis_valid && hdmi_axis_user) diag_frame_toggle<=~diag_frame_toggle;


    m9_startup_observer u_startup_diag(


        .clk_50m(clk_50m),.ext_rst_n(sys_rst_n),


        .clock_toggles_async({diag_serial_count[15],diag_video_count[9],diag_mem_count[9],diag_sys_count[9]}),


        .state_async({video_clocks_ready,sys_clocks_ready,hdmi_pll_lock,sys_pll_locked,


                      !rst_hdmi_serial,!rst_hdmi,!rst_video,!rst_sys}),


        .identity_async({sys_rst_n,media_epoch_reset_sys,wipe_identity_valid_video,!rst_identity_video}),


        .stream_async({diag_frame_toggle,hdmi_axis_valid,adt_valid,lock_tick_50m}),


        .de_async(de),.led_heartbeat(led_startup_50m),


        .seg_n(seg7_cathode),.dig_n(seg7_anode));





    // =========================================================================


    // Diagnostic LED1/A4 is driven only by u_startup_diag; no functional feedback.


    // =========================================================================





endmodule





// Keep the frozen-D1 Audio sample and synchronous envelope-read edges while the


// complete pixel packet reaches the unchanged renderer two clocks later.


module m9_audio_monitor_phase_adapter (


    input wire clk,input wire rst_state,input wire rst_epoch,


    input wire early_valid,input wire early_user,input wire [14:0] early_x,


    input wire monitor_enable_pending,input wire [7:0] write_ptr_pending,


    input wire [8:0] point_count_pending,input wire [15:0] latest_peak_pending,


    input wire [1:0] clip_id_pending,input wire play_active_pending,


    input wire [47:0] envelope_read_data,output wire [7:0] envelope_read_addr,


    output wire monitor_enable_aligned,output wire [7:0] write_ptr_aligned,


    output wire [8:0] point_count_aligned,output wire [15:0] latest_peak_aligned,


    output wire [1:0] clip_id_aligned,output wire play_active_aligned,


    output wire [47:0] envelope_read_data_aligned


);


    wire early_first=early_valid && early_user;


    reg [7:0] write_ptr_q;


    reg [8:0] point_count_q;


    wire [7:0] write_ptr_active=early_first ? write_ptr_pending : write_ptr_q;


    wire [8:0] point_count_active=early_first ? point_count_pending : point_count_q;


    wire [8:0] visible_count=point_count_active>=9'd128 ? 9'd128 : point_count_active;


    wire [7:0] first_column=8'd128-visible_count[7:0];


    wire [14:0] monitor_x=early_x-15'd224;


    wire [7:0] monitor_column={1'b0,monitor_x[9:3]};


    wire column_has_point=early_x>=224 && early_x<1248 && visible_count!=0 &&


                          monitor_column>=first_column;


    wire [7:0] oldest_address=write_ptr_active-visible_count[7:0];


    assign envelope_read_addr=column_has_point ?


        oldest_address+(monitor_column-first_column) : 8'd0;





    wire [36:0] pending_bundle={monitor_enable_pending,write_ptr_pending,


        point_count_pending,latest_peak_pending,clip_id_pending,play_active_pending};


    reg [36:0] pending_d1,pending_d2;


    assign {monitor_enable_aligned,write_ptr_aligned,point_count_aligned,


        latest_peak_aligned,clip_id_aligned,play_active_aligned}=pending_d2;


    always @(posedge clk or posedge rst_state) begin


        if(rst_state) begin


            write_ptr_q<=0;point_count_q<=0;pending_d1<=0;pending_d2<=0;


        end else begin


            if(early_first) begin


                write_ptr_q<=write_ptr_pending;point_count_q<=point_count_pending;


            end


            pending_d1<=pending_bundle;pending_d2<=pending_d1;


        end


    end





    reg [47:0] read_data_d1,read_data_d2;


    assign envelope_read_data_aligned=read_data_d2;


    always @(posedge clk or posedge rst_epoch) begin


        if(rst_epoch) begin read_data_d1<=0;read_data_d2<=0;end


        else begin read_data_d1<=envelope_read_data;read_data_d2<=read_data_d1;end


    end


endmodule





// Diagnostic-only display: raw reference clock, independent of functional resets.


module m9_startup_observer #(


    parameter integer WINDOW_CYCLES=5000000,


    parameter integer SCAN_CYCLES=8192,


    parameter integer HEARTBEAT_CYCLES=12500000


)(


    input wire clk_50m,input wire ext_rst_n,


    input wire [3:0] clock_toggles_async,


    input wire [7:0] state_async,input wire [3:0] identity_async,


    input wire [3:0] stream_async,input wire de_async,


    output wire led_heartbeat,


    output reg [7:0] seg_n,output reg [5:0] dig_n


);


    localparam WW=WINDOW_CYCLES<=1 ? 1 : $clog2(WINDOW_CYCLES);


    localparam SW=SCAN_CYCLES<=1 ? 1 : $clog2(SCAN_CYCLES);


    localparam HW=HEARTBEAT_CYCLES<=1 ? 1 : $clog2(HEARTBEAT_CYCLES);


    (* ASYNC_REG="TRUE" *) reg [20:0] status_meta,status_sync;


    reg [3:0] previous_clocks;


    reg [3:0] window_clocks,window_stream,recent_clocks,recent_stream;


    reg [WW-1:0] window_count;


    reg [SW-1:0] scan_count;


    reg [HW-1:0] heartbeat_count;


    reg heartbeat;


    reg [2:0] scan_index;


    wire [3:0] clock_events=status_sync[19:16]^previous_clocks;


    // Only transitions count as activity; a static high must age out.


    reg [3:0] previous_stream;


    reg previous_de,window_de,recent_de;


    wire [3:0] stream_events=status_sync[3:0]^previous_stream;


    wire de_event=status_sync[20]^previous_de;


    wire adt_stuck_high=status_sync[1] && !recent_stream[1];


    wire hdmi_stuck_high=status_sync[2] && !recent_stream[2];


    wire de_stuck_high=status_sync[20] && !recent_de;


    assign led_heartbeat=heartbeat; // Board LED1/A4: high lights, low extinguishes.


    wire [5:0] decimal_points={1'b0,de_stuck_high,hdmi_stuck_high,


                               adt_stuck_high,recent_de,heartbeat};


    wire [23:0] display_word={4'ha,status_sync[15:12],recent_clocks,


                             status_sync[11:8],recent_stream,status_sync[7:4]};


    reg [3:0] symbol;


    function [6:0] font;


        input [3:0] value;


        begin


            case(value)


                0:font=7'h3f;1:font=7'h06;2:font=7'h5b;3:font=7'h4f;


                4:font=7'h66;5:font=7'h6d;6:font=7'h7d;7:font=7'h07;


                8:font=7'h7f;9:font=7'h6f;10:font=7'h77;11:font=7'h7c;


                12:font=7'h39;13:font=7'h5e;14:font=7'h79;15:font=7'h71;


            endcase


        end


    endfunction


    always @* begin


        case(scan_index)


            0:symbol=display_word[23:20];1:symbol=display_word[19:16];


            2:symbol=display_word[15:12];3:symbol=display_word[11:8];


            4:symbol=display_word[7:4];default:symbol=display_word[3:0];


        endcase


    end


    always @(posedge clk_50m or negedge ext_rst_n) begin


        if(!ext_rst_n) begin status_meta<=0;status_sync<=0;end


        else begin


            status_meta<={de_async,clock_toggles_async,state_async,identity_async,stream_async};


            status_sync<=status_meta;


        end


    end


    always @(posedge clk_50m or negedge ext_rst_n) begin


        if(!ext_rst_n) begin


            previous_clocks<=0;previous_stream<=0;window_clocks<=0;window_stream<=0;


            previous_de<=0;window_de<=0;recent_de<=0;


            recent_clocks<=0;recent_stream<=0;window_count<=0;


        end else begin


            previous_clocks<=status_sync[19:16];previous_stream<=status_sync[3:0];


            previous_de<=status_sync[20];


            if(window_count==WINDOW_CYCLES-1) begin


                recent_clocks<=window_clocks|clock_events;


                recent_stream<=window_stream|stream_events;


                recent_de<=window_de|de_event;window_de<=0;


                window_count<=0;window_clocks<=0;window_stream<=0;


            end else begin


                window_count<=window_count+1'b1;


                window_clocks<=window_clocks|clock_events;


                window_stream<=window_stream|stream_events;


                window_de<=window_de|de_event;


            end


        end


    end


    always @(posedge clk_50m or negedge ext_rst_n) begin


        if(!ext_rst_n) begin heartbeat_count<=0;heartbeat<=0;end


        else if(heartbeat_count==HEARTBEAT_CYCLES-1) begin


            heartbeat_count<=0;heartbeat<=~heartbeat;


        end else heartbeat_count<=heartbeat_count+1'b1;


    end


    always @(posedge clk_50m or negedge ext_rst_n) begin


        if(!ext_rst_n) begin


            scan_count<=0;scan_index<=0;seg_n<=8'hff;dig_n<=6'h3f;


        end else begin


            if(scan_count==SCAN_CYCLES-1) begin


                scan_count<=0;scan_index<=scan_index==5 ? 0 : scan_index+1'b1;


            end else scan_count<=scan_count+1'b1;


            dig_n<=~(6'b000001<<scan_index);


            seg_n<={~decimal_points[scan_index],~font(symbol)};


        end


    end


endmodule


