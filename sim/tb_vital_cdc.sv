`timescale 1ns/1ps
module tb_vital_cdc;
    reg sc=0,dc=0;always #5 sc=~sc;always #7 dc=~dc;
    reg sr=1,dr=1,su=0,commit=1;reg [64:0] source=0;
    wire busy,du;wire [64:0] dest;
    integer i,seen=0;
    function [64:0] encode(input [7:0] x);encode={^x,{8{x}}};endfunction
    m9_vital_snapshot_cdc dut(.src_clk(sc),.src_rst(sr),.src_data(source),.src_update(su),.src_busy(busy),
        .dst_clk(dc),.dst_rst(dr),.dst_commit(commit),.dst_data(dest),.dst_update(du));
    always @(posedge dc) if(!dr && du) begin
        if(dest!==encode(dest[7:0])) $fatal(1,"torn snapshot %h",dest);
        seen=seen+1;
    end
    task flush(input [7:0] target);
        begin
            repeat(120) @(negedge dc);
            if(dest!==encode(target)) $fatal(1,"latest snapshot lost expected %0d got %h",target,dest);
        end
    endtask
    initial begin
        repeat(5) @(negedge sc);sr=0;
        repeat(5) @(negedge dc);dr=0;flush(0);
        for(i=1;i<=150;i=i+1) begin @(negedge sc);source=encode(i);su=1;end
        @(negedge sc);su=0;flush(150);$display("PASS atomic burst coalescing");
        @(negedge dc);commit=0;
        @(negedge sc);source=encode(201);su=1;@(negedge sc);su=0;
        repeat(30) @(negedge dc);
        if(dest!==encode(150)) $fatal(1,"commit stall");
        commit=1;flush(201);$display("PASS destination commit stall");
        @(negedge sc);sr=1;source=0;
        repeat(8) @(negedge dc);
        if(dest!==0) $fatal(1,"source reset did not invalidate");
        @(negedge sc);sr=0;source=encode(77);flush(77);$display("PASS independent source reset");
        @(negedge dc);dr=1;repeat(8) @(negedge dc);dr=0;flush(77);
        $display("PASS independent destination reset, snapshots=%0d",seen);$finish;
    end
endmodule
