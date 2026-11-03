`timescale 1ns/1ps
// Acquisition and DSP run in sys_clk; atomic value snapshots cross to video_clk.
module m9_vital_processing_subsystem #(
    parameter integer I2C_QUARTER_CYCLES=63,
    parameter integer BUS_TIMEOUT_CYCLES=500000,
    parameter integer RESET_WAIT_CYCLES=1000000,
    parameter integer POLL_CYCLES=200000,
    parameter integer RETRY_CYCLES=10000000,
    parameter integer SAMPLE_TIMEOUT_CYCLES=50000000,
    parameter integer CAL_A_Q8=28160,CAL_B_Q8=6400
)(
    input wire sys_clk,input wire sys_rst,input wire video_clk,input wire video_rst,
    inout wire vital_i2c_scl,inout wire vital_i2c_sda,
    output wire [7:0] hr_bpm,output wire [7:0] spo2_percent,output wire [7:0] rr_bpm,
    output wire hr_valid,output wire spo2_valid,output wire rr_valid,
    output wire [11:0] hr_bcd,output wire [11:0] spo2_bcd,output wire [11:0] rr_bcd,
    output wire [1:0] data_source,output wire monitor_update,
    output wire sensor_ready,output wire [7:0] sensor_fault
);
    wire sample_valid,sample_ready,sample_gap;
    wire [17:0] red_sample,ir_sample;
    m9_max3010x_acquisition #(.QUARTER_CYCLES(I2C_QUARTER_CYCLES),
        .BUS_TIMEOUT_CYCLES(BUS_TIMEOUT_CYCLES),.RESET_WAIT_CYCLES(RESET_WAIT_CYCLES),
        .POLL_CYCLES(POLL_CYCLES),.RETRY_CYCLES(RETRY_CYCLES)) u_sensor(
        .clk(sys_clk),.rst(sys_rst),.scl(vital_i2c_scl),.sda(vital_i2c_sda),
        .sample_ready(sample_ready),.sample_valid(sample_valid),.red_sample(red_sample),.ir_sample(ir_sample),
        .sample_gap(sample_gap),.sensor_ready(sensor_ready),.fault_code(sensor_fault));
    wire [7:0] sys_hr,sys_spo2,sys_rr;
    wire sys_hr_valid,sys_spo2_valid,sys_rr_valid,sys_update;
    wire [11:0] sys_hr_bcd,sys_spo2_bcd,sys_rr_bcd;
    wire [1:0] sys_source;
    m9_ppg_vitals #(.SAMPLE_HZ(100),.SAMPLE_TIMEOUT_CYCLES(SAMPLE_TIMEOUT_CYCLES),
        .CAL_A_Q8(CAL_A_Q8),.CAL_B_Q8(CAL_B_Q8)) u_algorithm(
        .clk(sys_clk),.rst(sys_rst),.sample_valid(sample_valid && sample_ready),.sample_gap(sample_gap),
        .red_sample(red_sample),.ir_sample(ir_sample),.sample_ready(sample_ready),
        .hr_bpm(sys_hr),.spo2_percent(sys_spo2),.rr_bpm(sys_rr),
        .hr_valid(sys_hr_valid),.spo2_valid(sys_spo2_valid),.rr_valid(sys_rr_valid),
        .hr_bcd(sys_hr_bcd),.spo2_bcd(sys_spo2_bcd),.rr_bcd(sys_rr_bcd),
        .data_source(sys_source),.monitor_update(sys_update));
    wire [64:0] src_values={sys_hr,sys_spo2,sys_rr,sys_hr_valid,sys_spo2_valid,sys_rr_valid,
        sys_source,sys_hr_bcd,sys_spo2_bcd,sys_rr_bcd};
    wire [64:0] dst_values;
    wire snapshot_busy;
    m9_vital_snapshot_cdc #(.WIDTH(65)) u_snapshot(
        .src_clk(sys_clk),.src_rst(sys_rst),.src_data(src_values),.src_update(sys_update),.src_busy(snapshot_busy),
        .dst_clk(video_clk),.dst_rst(video_rst),.dst_commit(1'b1),.dst_data(dst_values),.dst_update(monitor_update));
    assign {hr_bpm,spo2_percent,rr_bpm,hr_valid,spo2_valid,rr_valid,
        data_source,hr_bcd,spo2_bcd,rr_bcd}=dst_values;
endmodule
