`timescale 1ns/1ps
// Behavioral I2C/FIFO peripheral used only by the HDL testbench.
module max3010x_model(inout wire scl,inout wire sda,input wire present,input wire stretch);
    reg drive_low=0;
    assign sda=drive_low ? 1'b0 : 1'bz;
    assign scl=stretch ? 1'b0 : 1'bz;
    reg [7:0] registers[0:255];
    reg [17:0] reds[0:31],irs[0:31];
    integer i,mode=0,next_mode=0,ack_phase=0,bit_count=0,tx_bit=7,fifo_offset=0;
    reg [7:0] shift=0,pointer=0,txbyte=0;
    reg active=0,ack_value=0,read_ack=0;
    initial begin
        for(i=0;i<256;i=i+1) registers[i]=0;
        registers[255]=8'h15;
    end
    task push_sample(input [17:0] red,input [17:0] ir);
        integer w,n;
        begin
            w=registers[4]&31;n=(w+1)&31;
            if(n==(registers[6]&31)) registers[5]=(registers[5]+1)&31;
            else begin reds[w]=red;irs[w]=ir;registers[4]=n;end
        end
    endtask
    function [7:0] read_current;
        integer r;
        begin
            if(pointer==7) begin
                r=registers[6]&31;
                case(fifo_offset)
                    0:read_current={6'd0,reds[r][17:16]};1:read_current=reds[r][15:8];
                    2:read_current=reds[r][7:0];3:read_current={6'd0,irs[r][17:16]};
                    4:read_current=irs[r][15:8];default:read_current=irs[r][7:0];
                endcase
            end else read_current=registers[pointer];
        end
    endfunction
    task advance_read;
        begin
            if(pointer==7) begin
                if(fifo_offset==5) begin registers[6]=(registers[6]+1)&31;fifo_offset=0;end
                else fifo_offset=fifo_offset+1;
            end else pointer=pointer+1'b1;
        end
    endtask
    always @(negedge sda) if(scl===1'b1) begin
        active=1;mode=0;ack_phase=0;bit_count=0;shift=0;drive_low=0;
    end
    always @(posedge sda) if(scl===1'b1) begin active=0;drive_low=0;end
    always @(posedge scl) if(active) begin
        if(mode<=2 && ack_phase==0) begin
            shift={shift[6:0],sda};bit_count=bit_count+1;
            if(bit_count==8) begin
                ack_value=present;
                if(mode==0) begin
                    ack_value=present && shift[7:1]==7'h57;
                    next_mode=shift[0] ? 3 : 1;
                end else if(mode==1) begin pointer=shift;fifo_offset=0;next_mode=2;end
                else begin
                    registers[pointer]=shift;
                    if(pointer==9 && shift[6]) begin
                        registers[9]=0;registers[4]=0;registers[5]=0;registers[6]=0;
                    end
                    pointer=pointer+1'b1;next_mode=2;
                end
                ack_phase=1;
            end
        end else if(mode==3) begin
            bit_count=bit_count+1;
        end else if(mode==4) begin read_ack=!sda;end
    end
    always @(negedge scl) if(active) begin
        if(ack_phase==1) begin drive_low=ack_value;ack_phase=2;end
        else if(ack_phase==2) begin
            drive_low=0;ack_phase=0;bit_count=0;
            if(!ack_value) mode=5;
            else begin
                mode=next_mode;
                if(mode==3) begin txbyte=read_current();tx_bit=7;drive_low=!txbyte[7];end
            end
        end else if(mode==3) begin
            if(bit_count==8) begin drive_low=0;advance_read();mode=4;read_ack=0;end
            else begin tx_bit=7-bit_count;drive_low=!txbyte[tx_bit];end
        end else if(mode==4) begin
            if(read_ack) begin
                mode=3;bit_count=0;txbyte=read_current();drive_low=!txbyte[7];
            end else begin drive_low=0;mode=5;end
        end
    end
endmodule
