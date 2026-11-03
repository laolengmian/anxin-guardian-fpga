`timescale 1ns/1ps
// Dual-wavelength PPG processing, fixed-point Q8 filters and bounded arithmetic.
// SpO2 = CAL_A - CAL_B * (RMS(red_AC)/red_DC)/(RMS(ir_AC)/ir_DC).
// Respiratory rate is estimated from low-frequency PPG baseline modulation.
module m9_ppg_vitals #(
    parameter integer SAMPLE_HZ=100,
    parameter integer SAMPLE_TIMEOUT_CYCLES=50000000,
    parameter integer WARMUP_SAMPLES=300,
    parameter integer MIN_DC=10000, MAX_DC=250000,
    parameter integer CAL_A_Q8=28160, CAL_B_Q8=6400
)(
    input wire clk,input wire rst,
    input wire sample_valid,input wire sample_gap,
    input wire [17:0] red_sample,input wire [17:0] ir_sample,
    output wire sample_ready,
    output wire [7:0] hr_bpm,output reg [7:0] spo2_percent,output wire [7:0] rr_bpm,
    output wire hr_valid,output reg spo2_valid,output wire rr_valid,
    output wire [11:0] hr_bcd,output wire [11:0] spo2_bcd,output wire [11:0] rr_bcd,
    output wire [1:0] data_source,output reg monitor_update
);
    assign sample_ready=1'b1;
    reg [31:0] watchdog;
    wire timed_out=watchdog>=SAMPLE_TIMEOUT_CYCLES-1 && !sample_valid;
    wire contact_ok=red_sample>=MIN_DC && red_sample<=MAX_DC &&
                    ir_sample>=MIN_DC && ir_sample<=MAX_DC;
    wire clear_stream=sample_gap || timed_out || (sample_valid && !contact_ok);
    reg initialized;
    reg [15:0] warmup_count;
    wire enable=initialized && warmup_count>=WARMUP_SAMPLES && !clear_stream;
    assign data_source=enable ? 2'b10 : 2'b00;

    reg signed [26:0] red_dc,ir_dc,red_hp_dc,ir_hp_dc,red_lp,ir_lp;
    reg signed [26:0] resp_fast,resp_slow,resp_lp1,resp_lp2;
    wire signed [26:0] red_input=$signed({1'b0,red_sample,8'b0});
    wire signed [26:0] ir_input=$signed({1'b0,ir_sample,8'b0});
    wire signed [26:0] red_dc_next=red_dc+((red_input-red_dc)>>>4);
    wire signed [26:0] ir_dc_next=ir_dc+((ir_input-ir_dc)>>>4);
    wire signed [26:0] red_hp=red_input-red_dc_next;
    wire signed [26:0] ir_hp=ir_input-ir_dc_next;
    wire signed [26:0] red_hp_dc_next=red_hp_dc+((red_hp-red_hp_dc)>>>4);
    wire signed [26:0] ir_hp_dc_next=ir_hp_dc+((ir_hp-ir_hp_dc)>>>4);
    wire signed [26:0] red_lp_next=red_lp+(((red_hp-red_hp_dc_next)-red_lp)>>>2);
    wire signed [26:0] ir_lp_next=ir_lp+(((ir_hp-ir_hp_dc_next)-ir_lp)>>>2);
    wire signed [26:0] resp_fast_next=resp_fast+((ir_input-resp_fast)>>>6);
    wire signed [26:0] resp_slow_next=resp_slow+((resp_fast_next-resp_slow)>>>10);
    wire signed [26:0] resp_lp1_next=resp_lp1+(((resp_fast_next-resp_slow_next)-resp_lp1)>>>7);
    wire signed [26:0] resp_lp2_next=resp_lp2+((resp_lp1_next-resp_lp2)>>>7);
    wire signed [23:0] cardiac_value=ir_lp_next>>>8;
    wire signed [23:0] respiration_value=resp_lp2_next>>>8;
    wire signed [15:0] red_ac=red_lp_next>>>11;
    wire signed [15:0] ir_ac=ir_lp_next>>>11;
    wire [31:0] red_square=red_ac*red_ac;
    wire [31:0] ir_square=ir_ac*ir_ac;
    wire hr_update,rr_update;
    m9_ppg_rate_estimator #(.SAMPLE_HZ(SAMPLE_HZ),.MIN_BPM(35),.MAX_BPM(220),.MIN_ENVELOPE(64)) u_hr(
        .clk(clk),.rst(rst || clear_stream),.enable(enable),.sample_valid(sample_valid),
        .signal_value(cardiac_value),.rate_bpm(hr_bpm),.rate_valid(hr_valid),.rate_update(hr_update)
    );
    m9_ppg_rate_estimator #(.SAMPLE_HZ(SAMPLE_HZ),.MIN_BPM(6),.MAX_BPM(40),.MIN_ENVELOPE(64)) u_rr(
        .clk(clk),.rst(rst || clear_stream),.enable(enable),.sample_valid(sample_valid),
        .signal_value(respiration_value),.rate_bpm(rr_bpm),.rate_valid(rr_valid),.rate_update(rr_update)
    );

    reg [9:0] window_count;
    reg [41:0] red_energy,ir_energy;
    reg [27:0] red_dc_sum,ir_dc_sum;
    wire [41:0] red_energy_next=red_energy+red_square;
    wire [41:0] ir_energy_next=ir_energy+ir_square;
    wire [27:0] red_dc_sum_next=red_dc_sum+red_sample;
    wire [27:0] ir_dc_sum_next=ir_dc_sum+ir_sample;
    reg [3:0] calc_state;
    reg sqrt_start;
    reg [31:0] sqrt_input,ir_mean_square;
    wire sqrt_busy,sqrt_done;
    wire [15:0] sqrt_result;
    reg [15:0] red_rms,ir_rms;
    reg [17:0] red_mean,ir_mean;
    reg [33:0] ratio_numerator,ratio_denominator;
    reg ratio_start;
    wire ratio_busy,ratio_done,ratio_zero;
    wire [47:0] ratio_quotient;
    reg [15:0] ratio_q12;
    reg signed [39:0] calibrated_q20;
    wire signed [39:0] calibration_result=(calibrated_q20+40'sd524288)>>>20;
    reg spo2_update;
    wire calc_reset=rst || clear_stream || !enable;
    m9_integer_sqrt u_rms_sqrt(.clk(clk),.rst(calc_reset),.start(sqrt_start),.value(sqrt_input),
        .busy(sqrt_busy),.done(sqrt_done),.result(sqrt_result));
    m9_unsigned_divider #(.WIDTH(48)) u_ratio_divider(
        .clk(clk),.rst(calc_reset),.start(ratio_start),
        .numerator({2'b00,ratio_numerator,12'b0}),.denominator({14'b0,ratio_denominator}),
        .busy(ratio_busy),.done(ratio_done),.divide_by_zero(ratio_zero),.quotient(ratio_quotient));

    function [11:0] binary_bcd;
        input [7:0] value;
        reg [19:0] shift;
        integer i;
        begin
            shift={12'd0,value};
            for(i=0;i<8;i=i+1) begin
                if(shift[11:8]>=5) shift[11:8]=shift[11:8]+3;
                if(shift[15:12]>=5) shift[15:12]=shift[15:12]+3;
                if(shift[19:16]>=5) shift[19:16]=shift[19:16]+3;
                shift=shift<<1;
            end
            binary_bcd=shift[19:8];
        end
    endfunction
    assign hr_bcd=binary_bcd(hr_bpm);
    assign spo2_bcd=binary_bcd(spo2_percent);
    assign rr_bcd=binary_bcd(rr_bpm);
    reg [4:0] last_status;
    always @(posedge clk) begin
        if(rst) begin monitor_update<=0;last_status<=0;end
        else begin
            monitor_update<=hr_update || rr_update || spo2_update ||
                last_status!={data_source,hr_valid,spo2_valid,rr_valid};
            last_status<={data_source,hr_valid,spo2_valid,rr_valid};
        end
    end
    always @(posedge clk) begin
        if(rst) watchdog<=0;
        else if(sample_valid || sample_gap) watchdog<=0;
        else if(watchdog<SAMPLE_TIMEOUT_CYCLES) watchdog<=watchdog+1'b1;
    end
    always @(posedge clk) begin
        if(rst || clear_stream) begin
            initialized<=0;warmup_count<=0;
            red_dc<=0;ir_dc<=0;red_hp_dc<=0;ir_hp_dc<=0;red_lp<=0;ir_lp<=0;
            resp_fast<=0;resp_slow<=0;resp_lp1<=0;resp_lp2<=0;
            window_count<=0;red_energy<=0;ir_energy<=0;red_dc_sum<=0;ir_dc_sum<=0;
            calc_state<=0;sqrt_start<=0;sqrt_input<=0;ir_mean_square<=0;
            red_rms<=0;ir_rms<=0;red_mean<=0;ir_mean<=0;
            ratio_numerator<=0;ratio_denominator<=1;ratio_start<=0;ratio_q12<=0;
            calibrated_q20<=0;spo2_percent<=0;spo2_valid<=0;spo2_update<=0;
        end else begin
            sqrt_start<=0;ratio_start<=0;spo2_update<=0;
            if(!hr_valid) spo2_valid<=0;
            if(sample_valid) begin
                if(!initialized) begin
                    red_dc<=red_input;ir_dc<=ir_input;resp_fast<=ir_input;resp_slow<=ir_input;
                    initialized<=1;
                end else begin
                    if(warmup_count<WARMUP_SAMPLES) warmup_count<=warmup_count+1'b1;
                    red_dc<=red_dc_next;ir_dc<=ir_dc_next;
                    red_hp_dc<=red_hp_dc_next;ir_hp_dc<=ir_hp_dc_next;
                    red_lp<=red_lp_next;ir_lp<=ir_lp_next;
                    resp_fast<=resp_fast_next;resp_slow<=resp_slow_next;
                    resp_lp1<=resp_lp1_next;resp_lp2<=resp_lp2_next;
                    if(enable) begin
                        if(window_count==1023) begin
                            window_count<=0;red_energy<=0;ir_energy<=0;red_dc_sum<=0;ir_dc_sum<=0;
                            if(calc_state==0) begin
                                sqrt_input<=red_energy_next>>10;ir_mean_square<=ir_energy_next>>10;
                                red_mean<=red_dc_sum_next>>10;ir_mean<=ir_dc_sum_next>>10;
                                sqrt_start<=1;calc_state<=1;
                            end else begin spo2_valid<=0;spo2_update<=1;end
                        end else begin
                            window_count<=window_count+1'b1;
                            red_energy<=red_energy_next;ir_energy<=ir_energy_next;
                            red_dc_sum<=red_dc_sum_next;ir_dc_sum<=ir_dc_sum_next;
                        end
                    end
                end
            end
            case(calc_state)
                1: if(sqrt_done) begin
                    red_rms<=sqrt_result;sqrt_input<=ir_mean_square;sqrt_start<=1;calc_state<=2;
                end
                2: if(sqrt_done) begin ir_rms<=sqrt_result;calc_state<=3;end
                3: begin
                    ratio_numerator<=red_rms*ir_mean;ratio_denominator<=ir_rms*red_mean;
                    calc_state<=4;
                end
                4: begin
                    if(red_rms>=4 && ir_rms>=8 && red_mean>=MIN_DC && ir_mean>=MIN_DC &&
                       ({ir_rms,14'b0}>={12'b0,ir_mean}) && hr_valid && ratio_denominator!=0) begin
                        ratio_start<=1;calc_state<=5;
                    end else begin spo2_valid<=0;spo2_update<=1;calc_state<=0;end
                end
                5: if(ratio_done) begin
                    if(!ratio_zero && ratio_quotient>=819 && ratio_quotient<=6554) begin
                        ratio_q12<=ratio_quotient[15:0];calc_state<=6;
                    end else begin spo2_valid<=0;spo2_update<=1;calc_state<=0;end
                end
                6: begin
                    calibrated_q20<=($signed(CAL_A_Q8)*40'sd4096)-($signed(CAL_B_Q8)*$signed({1'b0,ratio_q12}));
                    calc_state<=7;
                end
                7: begin
                    if(calibration_result>=70 && calibration_result<=100 && hr_valid) begin
                        spo2_percent<=calibration_result[7:0];spo2_valid<=1;
                    end else spo2_valid<=0;
                    spo2_update<=1;calc_state<=0;
                end
                default: begin end
            endcase
        end
    end
endmodule
