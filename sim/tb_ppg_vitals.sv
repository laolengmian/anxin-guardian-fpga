`timescale 1ns/1ps
module tb_ppg_vitals #(parameter integer CAL_A_Q8=28160);
    reg clk=0;always #5 clk=~clk;
    reg rst=1,sample_valid=0,sample_gap=0;
    reg [17:0] red_sample=0,ir_sample=0;
    wire [7:0] hr,sp,rr;wire hv,sv,rv,ready,update;
    wire [11:0] hb,sb,rb;wire [1:0] source;
    m9_ppg_vitals #(.SAMPLE_TIMEOUT_CYCLES(1000),.CAL_A_Q8(CAL_A_Q8)) dut(
        .clk(clk),.rst(rst),.sample_valid(sample_valid),.sample_gap(sample_gap),
        .red_sample(red_sample),.ir_sample(ir_sample),.sample_ready(ready),
        .hr_bpm(hr),.spo2_percent(sp),.rr_bpm(rr),.hr_valid(hv),.spo2_valid(sv),.rr_valid(rv),
        .hr_bcd(hb),.spo2_bcd(sb),.rr_bcd(rb),.data_source(source),.monitor_update(update));
    string input_file,output_file;
    integer fd,fo,n,r,i;integer red_in,ir_in;
    function integer from_bcd(input [11:0] b);
        from_bcd=b[11:8]*100+b[7:4]*10+b[3:0];
    endfunction
    initial begin
        if(!$value$plusargs("INPUT=%s",input_file)) $fatal(1,"missing INPUT");
        if(!$value$plusargs("OUTPUT=%s",output_file)) $fatal(1,"missing OUTPUT");
        if(!$value$plusargs("N=%d",n)) $fatal(1,"missing N");
        fd=$fopen(input_file,"r");fo=$fopen(output_file,"w");
        if(!fd || !fo) $fatal(1,"file open");
        $fdisplay(fo,"sample,hr,spo2,rr,hr_valid,spo2_valid,rr_valid");
        repeat(8) @(negedge clk);rst=0;
        for(i=0;i<n;i=i+1) begin
            r=$fscanf(fd,"%h %h",red_in,ir_in);
            if(r!=2) $fatal(1,"sample parse %d",i);
            @(negedge clk);red_sample=red_in;ir_sample=ir_in;sample_valid=1;
            @(negedge clk);sample_valid=0;
            repeat(119) @(negedge clk);
            if((hv && from_bcd(hb)!=hr) || (sv && from_bcd(sb)!=sp) || (rv && from_bcd(rb)!=rr))
                $fatal(1,"BCD mismatch at %d",i);
            if(i%100==99) $fdisplay(fo,"%0d,%0d,%0d,%0d,%0d,%0d,%0d",i+1,hr,sp,rr,hv,sv,rv);
        end
        repeat(1100) @(negedge clk);
        if(hv || sv || rv) $fatal(1,"sample timeout did not invalidate");
        $fclose(fd);$fclose(fo);$display("PASS waveform + BCD + stream timeout");$finish;
    end
endmodule
