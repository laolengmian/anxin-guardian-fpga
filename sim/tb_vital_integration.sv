`timescale 1ns/1ps
module tb_vital_integration;
    reg sys_clk=0,video_clk=0;always #5 sys_clk=~sys_clk;always #7 video_clk=~video_clk;
    reg sys_rst=1,video_rst=1,present=1;
    tri1 scl,sda;
    wire [7:0] hr,sp,rr,fault;wire hv,sv,rv,update,ready;
    wire [11:0] hb,sb,rb;wire [1:0] source;
    max3010x_model sensor(.scl(scl),.sda(sda),.present(present),.stretch(1'b0));
    m9_vital_processing_subsystem #(.I2C_QUARTER_CYCLES(3),.BUS_TIMEOUT_CYCLES(8000),
        .RESET_WAIT_CYCLES(30),.POLL_CYCLES(20),.RETRY_CYCLES(100),.SAMPLE_TIMEOUT_CYCLES(20000)) dut(
        .sys_clk(sys_clk),.sys_rst(sys_rst),.video_clk(video_clk),.video_rst(video_rst),
        .vital_i2c_scl(scl),.vital_i2c_sda(sda),.hr_bpm(hr),.spo2_percent(sp),.rr_bpm(rr),
        .hr_valid(hv),.spo2_valid(sv),.rr_valid(rv),.hr_bcd(hb),.spo2_bcd(sb),.rr_bcd(rb),
        .data_source(source),.monitor_update(update),.sensor_ready(ready),.sensor_fault(fault));
    reg [9:0] frame_phase=0;
    always @(posedge video_clk) if(video_rst) frame_phase<=0;else frame_phase<=frame_phase+1'b1;
    wire ov;wire [23:0] rgb;wire [14:0] ox,oy;wire ou,ol;
    m9_vital_monitor_overlay overlay(.clk(video_clk),.rst(video_rst),.in_valid(1'b1),.in_user(frame_phase==0),
        .in_last(1'b0),.in_x(15'd1080),.in_y(15'd244),.in_rgb(24'h123456),
        .diagnostic_pending(1'b0),.alert_active_pending(1'b0),.monitor_update(update),
        .hr_bpm(hr),.spo2_percent(sp),.rr_bpm(rr),.hr_valid(hv),.spo2_valid(sv),.rr_valid(rv),
        .data_source(source),.hr_bcd(hb),.spo2_bcd(sb),.rr_bcd(rb),
        .brightness_level_pending(4'd4),.brightness_update(1'b0),
        .out_valid(ov),.out_user(ou),.out_last(ol),.out_x(ox),.out_y(oy),.out_rgb(rgb));
    string input_file,vcd_file;
    integer fd,r,red_in,ir_in,i,seen=0;
    always @(posedge video_clk) if(!video_rst && update) begin
        seen=seen+1;
        if(((^{hr,sp,rr,hv,sv,rv,hb,sb,rb,source}) === 1'bx)) $fatal(1,"unknown snapshot values=%h/%h/%h flags=%b%b%b bcd=%h/%h/%h source=%b packed=%h",hr,sp,rr,hv,sv,rv,hb,sb,rb,source,dut.dst_values);
    end
    initial begin
        if(!$value$plusargs("INPUT=%s",input_file)) $fatal(1,"missing INPUT");
        if($value$plusargs("VCD=%s",vcd_file)) begin
            $dumpfile(vcd_file);
            $dumpvars(0,hr,sp,rr,hv,sv,rv,update,source);
        end
        fd=$fopen(input_file,"r");if(!fd) $fatal(1,"input open");
        repeat(8) @(negedge sys_clk);sys_rst=0;
        repeat(8) @(negedge video_clk);video_rst=0;
        wait(ready);
        for(i=0;i<4500;i=i+1) begin
            r=$fscanf(fd,"%h %h",red_in,ir_in);if(r!=2) $fatal(1,"parse");
            @(negedge sys_clk);sensor.push_sample(red_in,ir_in);
            repeat(3500) @(negedge sys_clk);
        end
        repeat(2000) @(negedge video_clk);
        if(!hv || !sv || !rv || hr<70 || hr>74 || sp<96 || sp>100 || rr<10 || rr>14)
            $fatal(1,"end-to-end HR=%0d/%b SpO2=%0d/%b RR=%0d/%b",hr,hv,sp,sv,rr,rv);
        if(!overlay.frame_hr_valid || !overlay.frame_spo2_valid || !overlay.frame_rr_valid)
            $fatal(1,"display did not commit validity");
        $display("PASS sensor FIFO -> DSP -> async snapshot -> frame overlay HR=%0d SpO2=%0d RR=%0d snapshots=%0d",hr,sp,rr,seen);
        present=0;
        repeat(20000) @(negedge sys_clk);
        repeat(2200) @(negedge video_clk);
        if(hv || sv || rv || overlay.frame_hr_valid || overlay.frame_spo2_valid || overlay.frame_rr_valid)
            $fatal(1,"disconnect did not invalidate visible values");
        $display("PASS disconnect invalidation through display");
        $fclose(fd);$finish;
    end
    initial begin #2000000000;$fatal(1,"integration timeout");end
endmodule
