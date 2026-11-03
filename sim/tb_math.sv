`timescale 1ns/1ps
module tb_math;
    reg clk=0;always #5 clk=~clk;
    reg rst=1,ds=0,ss=0;reg [47:0] num=0,den=1;reg [31:0] value=0;
    wire db,dd,dz,sb,sd;wire [47:0] q;wire [15:0] root;
    m9_unsigned_divider #(.WIDTH(48)) div(.clk(clk),.rst(rst),.start(ds),.numerator(num),.denominator(den),
        .busy(db),.done(dd),.divide_by_zero(dz),.quotient(q));
    m9_integer_sqrt sqrt(.clk(clk),.rst(rst),.start(ss),.value(value),.busy(sb),.done(sd),.result(root));
    integer i;reg [63:0] lower,upper;reg [47:0] expected;
    initial begin
        repeat(5) @(negedge clk);rst=0;
        for(i=0;i<200;i=i+1) begin
            @(negedge clk);num={$random,$random};den={$random,$random};
            if(i==0) den=0;if(i==1) begin num=48'hffffffffffff;den=1;end
            expected=den==0 ? 0 : num/den;ds=1;
            @(negedge clk);ds=0;wait(dd);#1;
            if(q!==expected || dz!==(den==0)) $fatal(1,"division %d",i);
            @(negedge clk);value=$random;if(i==0) value=0;if(i==1) value=32'hffffffff;ss=1;
            @(negedge clk);ss=0;wait(sd);#1;
            lower=root;lower=lower*lower;upper=root;upper=(upper+1)*(upper+1);
            if(lower>value || upper<=value) $fatal(1,"sqrt %d",i);
        end
        @(negedge clk);ds=1;ss=1;@(negedge clk);ds=0;ss=0;
        repeat(3) @(negedge clk);rst=1;@(negedge clk);
        if(db || sb || dd || sd) $fatal(1,"arithmetic reset abort");
        $display("PASS 200 divisions + 200 square roots + reset abort");$finish;
    end
endmodule
