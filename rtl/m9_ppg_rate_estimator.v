`timescale 1ns/1ps
// Adaptive Schmitt crossings and four complete inter-pulse intervals.
module m9_ppg_rate_estimator #(
    parameter integer SAMPLE_HZ=100, MIN_BPM=35, MAX_BPM=220,
    parameter integer MIN_ENVELOPE=64
)(
    input wire clk,input wire rst,input wire enable,input wire sample_valid,
    input wire signed [23:0] signal_value,
    output reg [7:0] rate_bpm,output reg rate_valid,output reg rate_update
);
    localparam [31:0] RATE_NUMERATOR=60*SAMPLE_HZ*4;
    localparam integer MIN_PERIOD=(60*SAMPLE_HZ+MAX_BPM-1)/MAX_BPM;
    localparam integer MAX_PERIOD=60*SAMPLE_HZ/MIN_BPM;
    reg [23:0] envelope;
    wire [23:0] magnitude=signal_value[23] ? -signal_value : signal_value;
    wire signed [24:0] envelope_delta=$signed({1'b0,magnitude})-$signed({1'b0,envelope});
    wire [23:0] threshold=envelope/2 < MIN_ENVELOPE/2 ? MIN_ENVELOPE/2 : envelope/2;
    reg armed,have_peak;
    reg [15:0] period_count,p0,p1,p2,p3;
    reg [2:0] accepted_count;
    reg [31:0] period_sum;
    wire [15:0] measured_period=period_count+1'b1;
    wire [31:0] next_sum=period_sum-p3+measured_period;
    reg divide_start,division_pending;
    reg [31:0] divide_denominator;
    wire divide_busy,divide_done,divide_zero;
    wire [31:0] divide_quotient;
    m9_unsigned_divider #(.WIDTH(32)) u_rate_divider(
        .clk(clk),.rst(rst || !enable),.start(divide_start),
        .numerator(RATE_NUMERATOR),.denominator(divide_denominator),
        .busy(divide_busy),.done(divide_done),.divide_by_zero(divide_zero),.quotient(divide_quotient)
    );
    always @(posedge clk) begin
        if(rst || !enable) begin
            envelope<=0;armed<=0;have_peak<=0;period_count<=0;
            p0<=0;p1<=0;p2<=0;p3<=0;accepted_count<=0;period_sum<=0;
            divide_start<=0;division_pending<=0;divide_denominator<=1;
            rate_bpm<=0;rate_valid<=0;rate_update<=0;
        end else begin
            divide_start<=0;rate_update<=0;
            if(divide_done && division_pending && !divide_zero && have_peak && period_count<=MAX_PERIOD) begin
                division_pending<=0;
                if(divide_quotient>=MIN_BPM && divide_quotient<=MAX_BPM) begin
                    rate_bpm<=divide_quotient[7:0];rate_valid<=1;rate_update<=1;
                end
            end
            if(sample_valid) begin
                envelope<=$signed({1'b0,envelope})+(envelope_delta>>>6);
                if(period_count<MAX_PERIOD+2) period_count<=period_count+1'b1;
                if(have_peak && period_count>=MAX_PERIOD) begin
                    have_peak<=0;rate_valid<=0;rate_update<=1;division_pending<=0;
                    accepted_count<=0;period_sum<=0;p0<=0;p1<=0;p2<=0;p3<=0;
                end
                if(signal_value < -$signed({1'b0,threshold})) armed<=1;
                if(armed && signal_value>$signed({1'b0,threshold}) && envelope>=MIN_ENVELOPE) begin
                    armed<=0;
                    if(!have_peak || period_count>MAX_PERIOD) begin
                        have_peak<=1;period_count<=0;
                        accepted_count<=0;period_sum<=0;p0<=0;p1<=0;p2<=0;p3<=0;
                    end else if(measured_period>=MIN_PERIOD) begin
                        period_count<=0;
                        p3<=p2;p2<=p1;p1<=p0;p0<=measured_period;
                        period_sum<=next_sum;
                        if(accepted_count>0 && (measured_period*4<p0*3 || measured_period*4>p0*5)) begin
                            accepted_count<=0;period_sum<=0;p0<=0;p1<=0;p2<=0;p3<=0;
                            rate_valid<=0;rate_update<=1;division_pending<=0;
                        end else begin
                        if(accepted_count<4) accepted_count<=accepted_count+1'b1;
                        if(accepted_count>=3 && !divide_busy) begin
                            divide_denominator<=next_sum;divide_start<=1;division_pending<=1;
                        end
                        end
                    end
                end
            end
        end
    end
endmodule
