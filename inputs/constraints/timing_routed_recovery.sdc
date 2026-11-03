# ============================================================
# timing_4bank_m6c.sdc — M6-C FAT32/BMP四Bank时序约束
# 工程: anxin_guardian_4bank_m6c_fat32 (HX4S20C, EG4S20BG256)
# 继承v17已验证时钟、HDMI、FIFO reset与SDRAM硬核边界；新增CDC只允许
# 精确切源寄存器到第一同步级，后续同步级继续计时。
# 顶层: top_4bank_720p_m9_final_candidate（独立精简轮播候选）
# ============================================================

# 1. 板级输入主时钟
create_clock -name clk_50m -period 20 -waveform {0 10} [get_ports {clk_50m}]

# 2. 自动推导 PLL 输出时钟
derive_clocks

# 3. 给关键 PLL 输出命名（路径按本工程实例名）
rename_clock -name {sys_clk}   -source [get_ports {clk_50m}] -master_clock {clk_50m} [get_pins {u_sys_pll/pll_inst.clkc[0]}]
rename_clock -name {mem_clk}   -source [get_ports {clk_50m}] -master_clock {clk_50m} [get_pins {u_sys_pll/pll_inst.clkc[1]}]
rename_clock -name {mem_clk_sft} -source [get_ports {clk_50m}] -master_clock {clk_50m} [get_pins {u_sys_pll/pll_inst.clkc[2]}]
rename_clock -name {video_clk} -source [get_ports {clk_50m}] -master_clock {clk_50m} [get_pins {u_hdmi_pll/pll_inst.clkc[0]}]
rename_clock -name {hdmi_5x_clk} -source [get_ports {clk_50m}] -master_clock {clk_50m} [get_pins {u_hdmi_pll/pll_inst.clkc[1]}]
rename_clock -name {audio_mclk} -source [get_ports {clk_50m}] -master_clock {clk_50m} [get_pins {u_hdmi_pll/pll_inst.clkc[2]}]

# v2时钟架构：mem_clk=125M(C1) + mem_clk_sft=125M@180°(C2)，官方 sdr_as_ram
# 的刷新计数按125MHz宏烧，SDRAM控制器内部用同频反相时钟对，STA按同源
# 相关时钟处理（不设false path）。

# 4. 跨时钟域例外（与M6-A同源的精确寄存器级例外，实例名对应本顶层）：

# I2S 在 audio_mclk 域产生，由 video_clk 域三级同步器的第一级异步采样。
# 仅豁免源到第一级的亚稳态边界，其余各级与复位恢复/移除全部计时。
set_false_path \
    -from [get_regs {u_audio_tone/O_i2s_BCLK u_audio_tone/O_i2s_LRCK u_audio_tone/O_i2s_DOUT}] \
    -to [get_regs {u_i2s_receiver/S_i2s_bclk_1d u_i2s_receiver/S_i2s_lrck_1d u_i2s_receiver/S_i2s_dout_1d}]

# 每条串化通道的奇偶切换经两级同步器跨入375M域。
# 仅豁免源到第一级；S_odd_even_1d 之后全部计时。
set_false_path \
    -from [get_regs {u_hdmi_phy/u0_lane_lvds_10_1_hardened/S_odd_even u_hdmi_phy/u1_lane_lvds_10_1_hardened/S_odd_even u_hdmi_phy/u2_lane_lvds_10_1_hardened/S_odd_even u_hdmi_phy/u3_lane_lvds_10_1_hardened/S_odd_even}] \
    -to [get_regs {u_hdmi_phy/u0_lane_lvds_10_1_hardened/S_odd_even_1d u_hdmi_phy/u1_lane_lvds_10_1_hardened/S_odd_even_1d u_hdmi_phy/u2_lane_lvds_10_1_hardened/S_odd_even_1d u_hdmi_phy/u3_lane_lvds_10_1_hardened/S_odd_even_1d}]

# TMDS 数据在 75M 像素域保持一个像素周期稳定，串化器在第5个375M沿捕获；
# hold修正配对保留launch沿（M6-A STA验证过的同款约束）。
set_multicycle_path -setup \
    -from [get_clocks {video_clk}] \
    -to [get_regs {u_hdmi_phy/u0_lane_lvds_10_1_hardened/S_shift_data[0] u_hdmi_phy/u0_lane_lvds_10_1_hardened/S_shift_data[1] u_hdmi_phy/u0_lane_lvds_10_1_hardened/S_shift_data[2] u_hdmi_phy/u0_lane_lvds_10_1_hardened/S_shift_data[3] u_hdmi_phy/u0_lane_lvds_10_1_hardened/S_shift_data[4] u_hdmi_phy/u0_lane_lvds_10_1_hardened/S_shift_data[5] u_hdmi_phy/u0_lane_lvds_10_1_hardened/S_shift_data[6] u_hdmi_phy/u0_lane_lvds_10_1_hardened/S_shift_data[7] u_hdmi_phy/u0_lane_lvds_10_1_hardened/S_shift_data[8] u_hdmi_phy/u0_lane_lvds_10_1_hardened/S_shift_data[9] u_hdmi_phy/u1_lane_lvds_10_1_hardened/S_shift_data[0] u_hdmi_phy/u1_lane_lvds_10_1_hardened/S_shift_data[1] u_hdmi_phy/u1_lane_lvds_10_1_hardened/S_shift_data[2] u_hdmi_phy/u1_lane_lvds_10_1_hardened/S_shift_data[3] u_hdmi_phy/u1_lane_lvds_10_1_hardened/S_shift_data[4] u_hdmi_phy/u1_lane_lvds_10_1_hardened/S_shift_data[5] u_hdmi_phy/u1_lane_lvds_10_1_hardened/S_shift_data[6] u_hdmi_phy/u1_lane_lvds_10_1_hardened/S_shift_data[7] u_hdmi_phy/u1_lane_lvds_10_1_hardened/S_shift_data[8] u_hdmi_phy/u1_lane_lvds_10_1_hardened/S_shift_data[9] u_hdmi_phy/u2_lane_lvds_10_1_hardened/S_shift_data[0] u_hdmi_phy/u2_lane_lvds_10_1_hardened/S_shift_data[1] u_hdmi_phy/u2_lane_lvds_10_1_hardened/S_shift_data[2] u_hdmi_phy/u2_lane_lvds_10_1_hardened/S_shift_data[3] u_hdmi_phy/u2_lane_lvds_10_1_hardened/S_shift_data[4] u_hdmi_phy/u2_lane_lvds_10_1_hardened/S_shift_data[5] u_hdmi_phy/u2_lane_lvds_10_1_hardened/S_shift_data[6] u_hdmi_phy/u2_lane_lvds_10_1_hardened/S_shift_data[7] u_hdmi_phy/u2_lane_lvds_10_1_hardened/S_shift_data[8] u_hdmi_phy/u2_lane_lvds_10_1_hardened/S_shift_data[9] u_hdmi_phy/u3_lane_lvds_10_1_hardened/S_shift_data[0] u_hdmi_phy/u3_lane_lvds_10_1_hardened/S_shift_data[1] u_hdmi_phy/u3_lane_lvds_10_1_hardened/S_shift_data[2] u_hdmi_phy/u3_lane_lvds_10_1_hardened/S_shift_data[3] u_hdmi_phy/u3_lane_lvds_10_1_hardened/S_shift_data[4] u_hdmi_phy/u3_lane_lvds_10_1_hardened/S_shift_data[5] u_hdmi_phy/u3_lane_lvds_10_1_hardened/S_shift_data[6] u_hdmi_phy/u3_lane_lvds_10_1_hardened/S_shift_data[7] u_hdmi_phy/u3_lane_lvds_10_1_hardened/S_shift_data[8] u_hdmi_phy/u3_lane_lvds_10_1_hardened/S_shift_data[9]}] 5
set_multicycle_path -hold -end \
    -from [get_clocks {video_clk}] \
    -to [get_regs {u_hdmi_phy/u0_lane_lvds_10_1_hardened/S_shift_data[0] u_hdmi_phy/u0_lane_lvds_10_1_hardened/S_shift_data[1] u_hdmi_phy/u0_lane_lvds_10_1_hardened/S_shift_data[2] u_hdmi_phy/u0_lane_lvds_10_1_hardened/S_shift_data[3] u_hdmi_phy/u0_lane_lvds_10_1_hardened/S_shift_data[4] u_hdmi_phy/u0_lane_lvds_10_1_hardened/S_shift_data[5] u_hdmi_phy/u0_lane_lvds_10_1_hardened/S_shift_data[6] u_hdmi_phy/u0_lane_lvds_10_1_hardened/S_shift_data[7] u_hdmi_phy/u0_lane_lvds_10_1_hardened/S_shift_data[8] u_hdmi_phy/u0_lane_lvds_10_1_hardened/S_shift_data[9] u_hdmi_phy/u1_lane_lvds_10_1_hardened/S_shift_data[0] u_hdmi_phy/u1_lane_lvds_10_1_hardened/S_shift_data[1] u_hdmi_phy/u1_lane_lvds_10_1_hardened/S_shift_data[2] u_hdmi_phy/u1_lane_lvds_10_1_hardened/S_shift_data[3] u_hdmi_phy/u1_lane_lvds_10_1_hardened/S_shift_data[4] u_hdmi_phy/u1_lane_lvds_10_1_hardened/S_shift_data[5] u_hdmi_phy/u1_lane_lvds_10_1_hardened/S_shift_data[6] u_hdmi_phy/u1_lane_lvds_10_1_hardened/S_shift_data[7] u_hdmi_phy/u1_lane_lvds_10_1_hardened/S_shift_data[8] u_hdmi_phy/u1_lane_lvds_10_1_hardened/S_shift_data[9] u_hdmi_phy/u2_lane_lvds_10_1_hardened/S_shift_data[0] u_hdmi_phy/u2_lane_lvds_10_1_hardened/S_shift_data[1] u_hdmi_phy/u2_lane_lvds_10_1_hardened/S_shift_data[2] u_hdmi_phy/u2_lane_lvds_10_1_hardened/S_shift_data[3] u_hdmi_phy/u2_lane_lvds_10_1_hardened/S_shift_data[4] u_hdmi_phy/u2_lane_lvds_10_1_hardened/S_shift_data[5] u_hdmi_phy/u2_lane_lvds_10_1_hardened/S_shift_data[6] u_hdmi_phy/u2_lane_lvds_10_1_hardened/S_shift_data[7] u_hdmi_phy/u2_lane_lvds_10_1_hardened/S_shift_data[8] u_hdmi_phy/u2_lane_lvds_10_1_hardened/S_shift_data[9] u_hdmi_phy/u3_lane_lvds_10_1_hardened/S_shift_data[0] u_hdmi_phy/u3_lane_lvds_10_1_hardened/S_shift_data[1] u_hdmi_phy/u3_lane_lvds_10_1_hardened/S_shift_data[2] u_hdmi_phy/u3_lane_lvds_10_1_hardened/S_shift_data[3] u_hdmi_phy/u3_lane_lvds_10_1_hardened/S_shift_data[4] u_hdmi_phy/u3_lane_lvds_10_1_hardened/S_shift_data[5] u_hdmi_phy/u3_lane_lvds_10_1_hardened/S_shift_data[6] u_hdmi_phy/u3_lane_lvds_10_1_hardened/S_shift_data[7] u_hdmi_phy/u3_lane_lvds_10_1_hardened/S_shift_data[8] u_hdmi_phy/u3_lane_lvds_10_1_hardened/S_shift_data[9]}] 4

# 4.1 SDRAM硬核接口（mem_clk ↔ mem_clk_sft，2026-09-19 STA报告后逐条登记）：
#     sdr_as_ram官方封装在硬宏黑盒内用 mem_clk@0°/mem_clk_sft@180° 反相对自采样
#     dq。STA按半周期窗口报告硬宏接口伪违例；mem_clk_sft fanout=1（只到硬核
#     时钟脚），因此该例外天然局限于官方硬宏边界。
set_false_path -from [get_clocks {mem_clk}] -to [get_clocks {mem_clk_sft}]
set_false_path -from [get_clocks {mem_clk_sft}] -to [get_clocks {mem_clk}]

# 4.2 M9-C split reset release. Each qualified 50 MHz source crosses only to
#     the first release stage of its own clock family. Stage1 -> stage2 and all
#     functional reset recovery/removal remain timed.
set_false_path \
    -from [get_regs {u_split_lock_qualifier/sys_ready}] \
    -to [get_regs {u_sys_reset_release/release_stage1 u_mem_reset_release/release_stage1}]
set_false_path \
    -from [get_regs {u_split_lock_qualifier/video_ready}] \
    -to [get_regs {u_video_reset_release/release_stage1 u_hdmi_reset_release/release_stage1 u_hdmi_serial_reset_release/release_stage1 u_audio_reset_release/release_stage1}]
# 4.3 Legacy KEY2/KEY4 and reserved SW3 ports are inert in this candidate.
# They have no functional loads, so no timing exception is required.

# 4.4 四Bank初装载完成sticky：sys_clk源寄存器经cdc_bit_sync进入video_clk域，
#     仅豁免源Q到第一级同步器；sync_stage1→sync_stage2继续完整计时。
set_false_path \
    -from [get_regs {banks_initialized_sys}] \
    -to [get_regs {u_banks_initialized_sync/sync_stage1}]

# 4.5 媒体错误sticky从sys_clk进入video_clk媒体状态显示；只切第一同步级。
set_false_path \
    -from [get_regs {media_system_error_sys}] \
    -to [get_regs {u_media_error_sync/sync_stage1}]

# 4.6 KEY4长按亮度事件由sys_clk toggle进入video_clk。只切源toggle到
#     第一同步级；dst_sync_stage1→dst_sync_stage2和事件检测继续计时。
set_false_path \
    -from [get_regs {u_brightness_event_cdc/src_toggle}] \
    -to [get_regs {u_brightness_event_cdc/dst_sync_stage1}]

# 4.7 官方writer的write_finish仅在mem_clk域保持1拍（8ns），短于sys_clk
#     1拍（10ns），不能用电平2FF直接采样。M6-C按已板测M5/M6-A模式使用
#     cdc_event_toggle保留事件；只切源toggle到第一同步级，stage1→stage2及
#     seen比较继续计时。
set_false_path \
    -from [get_regs {u_write_finish_cdc/src_toggle}] \
    -to [get_regs {u_write_finish_cdc/dst_sync_stage1}]

# Recovery first-frame confirmation remains a media-local 75M -> 100M event.
# Only the source toggle to the first destination stage is excluded.
set_false_path \
    -from [get_regs {u_recovery_frame_cdc/src_toggle}] \
    -to [get_regs {u_recovery_frame_cdc/dst_sync_stage1}]

# The official frame reader fifo_aclr asynchronously reaches the RFIFO read-side
# reset synchronizer. Cut only these reset cells; pointer and data paths stay timed.
set_false_path \
    -from [get_regs {u_mem_reset_release/release_stage2 u_frame_service/u_frame_fifo_read/fifo_aclr}] \
    -to [get_regs {u_frame_service/u_read_fifo/u_read_fifo/asy_r_rst0 u_frame_service/u_read_fifo/u_read_fifo/asy_r_rst1}]

# 4.9 首轮v13真实STA新增登记：同一个mem域reset/fifo_aclr也异步到达写FIFO的
#     sys_clk写侧内部reset同步器。seed6在未豁免时报告
#     release_stage2→asy_w_rst1 recovery -0.446ns；该路径不是功能数据路径。
#     仅切reset源到asy_w_rst0/asy_w_rst1，asy_w_rst0→asy_w_rst1仍继续计时。
set_false_path \
    -from [get_regs {u_mem_reset_release/release_stage2 u_frame_service/u_frame_fifo_write/fifo_aclr}] \
    -to [get_regs {u_frame_service/u_write_fifo/asy_w_rst0 u_frame_service/u_write_fifo/asy_w_rst1}]

# 5. 待真实STA报告后按CDC登记表逐条评估的项（先不预置，不掩盖问题）：
#    - loader_v2内req_ack电平同步第一级（mem_clk→sys_clk）
#    - reset同步器恢复/移除及vendor FIFO其余异步复位边界
#    全部时钟同源于50M输入经两个PLL，不设broad clock group/false path。

# M6-E: captured wipe target status, mem -> video; return ack video -> mem.
# Only toggle source -> first synchronizer stage is cut. Payload remains timed.
set_false_path -from [get_regs {u_wipe_status/request_toggle}] -to [get_regs {u_wipe_status/request_sync1}]
set_false_path -from [get_regs {u_wipe_status/request_seen}] -to [get_regs {u_wipe_status/ack_sync1}]

# M7-B: image handshake, playback enable and final-sample status.
# Only named source -> first stage; held payload and later stages stay timed.
set_false_path -from [get_regs {u_audio_select/request_toggle}] -to [get_regs {u_audio_select/request_sync1}]
set_false_path -from [get_regs {u_audio_select/request_seen}] -to [get_regs {u_audio_select/ack_sync1}]
set_false_path -from [get_regs {u_audio_loader/play_enable}] -to [get_regs {u_audio_enable_sync/sync_stage1}]
set_false_path -from [get_regs {u_pcm_player/write_closed}] -to [get_regs {u_pcm_player/closed_sync1}]

# M7-B reset-only boundary, justified by timing_attempt2 routed seed 1:
# sys release -> PCM read-side reset synchronizer SR pins has recovery -1.465 ns.
# These named cells asynchronously ASSERT reset and synchronously RELEASE it.
# Raw sources only connect to their reset inputs, not their shift-chain data.
# As with the inherited RFIFO reset boundary, cut only these source/reset-cell
# pairs. Local guard/FIFO stage-to-stage data and ALL functional recovery remain
# timed. No functional PCM register, clock group, or held payload is excluded.
set_false_path -from [get_regs {u_sys_reset_release/release_stage2 u_audio_loader/pipeline_reset}] -to [get_regs {u_pcm_player/rd_release[0] u_pcm_player/rd_release[1] u_pcm_player/rd_release[2] u_pcm_player/u_fifo/asy_r_rst0 u_pcm_player/u_fifo/asy_r_rst1}]

# M7-C clip identity: sys -> video request and return acknowledgement.
# Only toggle source to first stage; later stages and payload remain timed.
set_false_path -from [get_regs {u_subtitle_clip/request_toggle}] -to [get_regs {u_subtitle_clip/request_sync1}]
set_false_path -from [get_regs {u_subtitle_clip/request_seen}] -to [get_regs {u_subtitle_clip/ack_sync1}]

# M8-A/M9 asynchronous switches. Prior native Gate reports prove one packed
# input register per port with these exact PAD pins. Each exception ends at the
# PAD input stage; downstream PAD clk2q and synchronizer logic remain timed.
set_false_path -from [get_ports {sw_warning}]     -to [get_pins {sw_warning_syn_4.ipad}]
set_false_path -from [get_ports {sw_emergency}]     -to [get_pins {sw_emergency_syn_4.ipad}]

# M8-A immutable event request and aggregated ack. Only source toggle to first
# synchronization stage is cut; second stages and the held 19-bit payload stay timed.
set_false_path -from [get_regs {u_m8_event_commit/src_request_toggle}] -to [get_regs {u_m8_event_commit/dst_request_sync_stage1}]
set_false_path -from [get_regs {u_m8_event_commit/dst_ack_toggle}] -to [get_regs {u_m8_event_commit/src_ack_sync_stage1}]

# Simplified media-policy pause into the 75 MHz sample boundary. Only the
# registered policy state -> first synchronizer stage is cut; later stages and
# all PCM/audio consumers remain timed. This is not a Health-domain CDC.
set_false_path -from [get_regs {u_media_recovery_policy/state[1]}] -to [get_regs {u_media_pause_sync/sync_stage1}]

# Qualified visible AXIS starvation and PCM playback starvation are media-local
# recovery inputs. Cut only each registered source to its first 100 MHz stage.
set_false_path -from [get_regs {read_underflow_qualified_video}] -to [get_regs {u_media_read_underflow_sync/sync_stage1}]
set_false_path -from [get_regs {u_pcm_player/underflow_sticky}] -to [get_regs {u_media_pcm_underflow_sync/sync_stage1}]

# Six external active-low keys. v4/v5 native reporting proved the exact packed
# PAD identities below and one port-origin path per key. Terminate each cut at
# the PAD input pin so no additional fanout can be silently excluded. PAD
# clk2q -> stage2 replicas and every debounce/functional path remain timed.
set_false_path -from [get_ports {key1_n}] -to [get_pins {key1_n_syn_4.ipad}]
set_false_path -from [get_ports {key2_n}] -to [get_pins {key2_n_syn_2.ipad}]
set_false_path -from [get_ports {key3_n}] -to [get_pins {key3_n_syn_2.ipad}]
set_false_path -from [get_ports {key4_n}] -to [get_pins {key4_n_syn_2.ipad}]
set_false_path -from [get_ports {key5_n}] -to [get_pins {key5_n_syn_2.ipad}]
set_false_path -from [get_ports {key6_n}] -to [get_pins {key6_n_syn_2.ipad}]


# Diagnostic-only asynchronous status sampling. Only dedicated first-stage D paths.
# Raw clock heartbeat toggles and sampled levels never drive functional logic.
# Second stage and all downstream observer logic remain timed.
set_false_path -from [get_clocks {sys_clk mem_clk video_clk hdmi_5x_clk}] -to [get_regs {u_startup_diag/status_meta[*]}]

# run_02 routed-checkpoint-only dedicated remote-reset SR entries.
# Recovery only; Removal, stage data and downstream reset checks retained.
set_false_path -setup -from [get_regs {u_video_reset_release/release_stage2}] -through [get_nets {u_audio_select/src_rst}] -to [get_pins {u_audio_select/src_reset_dst_sync2_reg_syn_5.sr}]
set_false_path -setup -from [get_regs {u_video_reset_release/release_stage2}] -through [get_nets {u_subtitle_clip/dst_rst_dup_4}] -to [get_pins {u_wipe_status/dst_reset_src_sync2_reg_syn_5.sr}]
