`timescale 1ns/1ps
module tb_acquisition;
    reg clk=0;always #5 clk=~clk;
    reg rst=1,present=1,stretch=0,ready=1;
    tri1 scl,sda;
    wire valid,gap,sensor_ready;wire [7:0] fault;wire [17:0] red,ir;
    integer received=0,gaps=0,i,goal;
    reg [17:0] expected_red[0:255],expected_ir[0:255];
    max3010x_model sensor(.scl(scl),.sda(sda),.present(present),.stretch(stretch));
    m9_max3010x_acquisition #(.QUARTER_CYCLES(3),.BUS_TIMEOUT_CYCLES(8000),
        .RESET_WAIT_CYCLES(30),.POLL_CYCLES(20),.RETRY_CYCLES(100)) dut(
        .clk(clk),.rst(rst),.scl(scl),.sda(sda),.sample_ready(ready),.sample_valid(valid),
        .red_sample(red),.ir_sample(ir),.sample_gap(gap),.sensor_ready(sensor_ready),.fault_code(fault));
    always @(posedge clk) if(!rst) begin
        if(gap) gaps=gaps+1;
        if(valid && ready) begin
            if(red!==expected_red[received] || ir!==expected_ir[received])
                $fatal(1,"FIFO mismatch %0d got %0d/%0d expected %0d/%0d",received,red,ir,expected_red[received],expected_ir[received]);
            received=received+1;
        end
    end
    initial begin #200000000;$fatal(1,"acquisition test timeout state=%0d fault=%0d",dut.state,fault);end
    task enqueue(input integer x);
        begin
            expected_red[x]=18'h12345+x;expected_ir[x]=18'h23456+x*3;
            sensor.push_sample(expected_red[x],expected_ir[x]);
        end
    endtask
    initial begin
        repeat(8) @(negedge clk);rst=0;
        wait(sensor_ready);@(negedge clk);
        if(sensor.registers[10]!==8'h27 || sensor.registers[9]!==8'h03 ||
           sensor.registers[12]!==8'h24 || sensor.registers[13]!==8'h24) $fatal(1,"sensor config");
        $display("PASS configuration");
        for(i=0;i<70;i=i+1) begin
            @(negedge clk);enqueue(i);wait(received==i+1);
        end
        $display("PASS red/IR byte order and FIFO pointer wrap, 70 samples");
        @(negedge clk);ready=0;enqueue(70);wait(valid);
        repeat(100) @(negedge clk);
        if(!valid || red!==expected_red[70]) $fatal(1,"backpressure payload");
        ready=1;wait(received==71);$display("PASS backpressure");
        @(negedge clk);goal=gaps+1;sensor.registers[5]=1;
        wait(gaps>=goal);wait(sensor_ready);$display("PASS overflow recovery");
        @(negedge clk);present=0;goal=gaps+1;
        wait(gaps>=goal);if(sensor_ready) $fatal(1,"NACK did not clear ready");
        @(negedge clk);present=1;wait(sensor_ready);$display("PASS missing device recovery");
        @(negedge clk);stretch=1;goal=gaps+1;
        repeat(80) @(negedge clk);stretch=0;
        repeat(7000) @(negedge clk);
        if(gaps!=goal-1 || !sensor_ready) $fatal(1,"short clock stretch");
        $display("PASS short clock stretching");
        @(negedge clk);stretch=1;wait(gaps>=goal);
        @(negedge clk);stretch=0;wait(sensor_ready);$display("PASS stuck bus timeout and recovery");
        $display("PASS acquisition suite");$finish;
    end
endmodule
