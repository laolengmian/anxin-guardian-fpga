`timescale 1ns/1ps
// Open-drain register access with repeated START, final NACK and clock stretching.
module m9_i2c_register_master #(
    parameter integer QUARTER_CYCLES=250,
    parameter integer TIMEOUT_CYCLES=500000
)(
    input wire clk,input wire rst,input wire request,
    input wire read_not_write,input wire [6:0] device_address,
    input wire [7:0] register_address,input wire [7:0] write_data,
    input wire [3:0] read_count,
    inout wire scl,inout wire sda,
    output reg busy,output reg done,output reg error,
    output reg [47:0] read_data
);
    reg scl_low,sda_low;
    assign scl=scl_low ? 1'b0 : 1'bz;
    assign sda=sda_low ? 1'b0 : 1'bz;
    (* ASYNC_REG="TRUE" *) reg scl_sync1,scl_sync2,sda_sync1,sda_sync2;
    reg [31:0] divider,watchdog;
    wire tick=divider>=QUARTER_CYCLES-1;
    reg [5:0] state;
    reg [2:0] bit_index;
    reg [7:0] tx,rx,reg_address,data_byte;
    reg [6:0] address;
    reg reading;
    reg [3:0] bytes_left;
    reg [1:0] phase;
    reg nack;
    localparam IDLE=0,START_WAIT=1,START_SDA=2,START_FALL=3,
        TX_LOW=4,TX_HIGH=5,TX_HOLD=6,TX_FALL=7,
        ACK_LOW=8,ACK_HIGH=9,ACK_SAMPLE=10,ACK_FALL=11,
        RESTART_LOW=12,RESTART_HIGH=13,RESTART_SDA=14,RESTART_FALL=15,
        RX_LOW=16,RX_HIGH=17,RX_SAMPLE=18,RX_FALL=19,
        MACK_LOW=20,MACK_HIGH=21,MACK_HOLD=22,MACK_FALL=23,
        STOP_LOW=24,STOP_HIGH=25,STOP_SDA=26,STOP_DONE=27;
    always @(posedge clk) begin
        if(rst) begin scl_sync1<=1;scl_sync2<=1;sda_sync1<=1;sda_sync2<=1;end
        else begin scl_sync1<=scl;scl_sync2<=scl_sync1;sda_sync1<=sda;sda_sync2<=sda_sync1;end
    end
    always @(posedge clk) begin
        if(rst) begin
            state<=IDLE;scl_low<=0;sda_low<=0;divider<=0;watchdog<=0;
            busy<=0;done<=0;error<=0;read_data<=0;tx<=0;rx<=0;
            reg_address<=0;data_byte<=0;address<=0;reading<=0;
            bytes_left<=0;phase<=0;bit_index<=7;nack<=0;
        end else begin
            done<=0;
            if(tick) divider<=0;else divider<=divider+1'b1;
            if(busy) watchdog<=watchdog+1'b1;else watchdog<=0;
            if(busy && watchdog>=TIMEOUT_CYCLES-1) begin
                state<=IDLE;scl_low<=0;sda_low<=0;busy<=0;done<=1;error<=1;
            end else if(state==IDLE) begin
                scl_low<=0;sda_low<=0;
                if(request) begin
                    address<=device_address;reg_address<=register_address;data_byte<=write_data;
                    reading<=read_not_write;bytes_left<=read_count;phase<=0;
                    tx<={device_address,1'b0};bit_index<=7;
                    error<=0;read_data<=0;busy<=1;watchdog<=0;divider<=0;
                    if(read_not_write && (read_count==0 || read_count>6)) begin
                        busy<=0;done<=1;error<=1;
                    end else state<=START_WAIT;
                end
            end else if(tick) begin
                case(state)
                    START_WAIT: if(scl_sync2 && sda_sync2) state<=START_SDA;
                    START_SDA: begin sda_low<=1;state<=START_FALL;end
                    START_FALL: begin scl_low<=1;state<=TX_LOW;end
                    TX_LOW: begin scl_low<=1;sda_low<=!tx[bit_index];state<=TX_HIGH;end
                    TX_HIGH: begin scl_low<=0;if(scl_sync2) state<=TX_HOLD;end
                    TX_HOLD: state<=TX_FALL;
                    TX_FALL: begin
                        scl_low<=1;
                        if(bit_index==0) state<=ACK_LOW;
                        else begin bit_index<=bit_index-1'b1;state<=TX_LOW;end
                    end
                    ACK_LOW: begin sda_low<=0;state<=ACK_HIGH;end
                    ACK_HIGH: begin scl_low<=0;if(scl_sync2) state<=ACK_SAMPLE;end
                    ACK_SAMPLE: begin nack<=sda_sync2;state<=ACK_FALL;end
                    ACK_FALL: begin
                        scl_low<=1;bit_index<=7;
                        if(nack) begin error<=1;state<=STOP_LOW;end
                        else if(phase==0) begin tx<=reg_address;phase<=1;state<=TX_LOW;end
                        else if(phase==1 && reading) state<=RESTART_LOW;
                        else if(phase==1) begin tx<=data_byte;phase<=2;state<=TX_LOW;end
                        else if(phase==3) begin rx<=0;state<=RX_LOW;end
                        else state<=STOP_LOW;
                    end
                    RESTART_LOW: begin sda_low<=0;state<=RESTART_HIGH;end
                    RESTART_HIGH: begin scl_low<=0;if(scl_sync2) state<=RESTART_SDA;end
                    RESTART_SDA: begin sda_low<=1;state<=RESTART_FALL;end
                    RESTART_FALL: begin
                        scl_low<=1;tx<={address,1'b1};phase<=3;bit_index<=7;state<=TX_LOW;
                    end
                    RX_LOW: begin sda_low<=0;state<=RX_HIGH;end
                    RX_HIGH: begin scl_low<=0;if(scl_sync2) state<=RX_SAMPLE;end
                    RX_SAMPLE: begin rx[bit_index]<=sda_sync2;state<=RX_FALL;end
                    RX_FALL: begin
                        scl_low<=1;
                        if(bit_index==0) state<=MACK_LOW;
                        else begin bit_index<=bit_index-1'b1;state<=RX_LOW;end
                    end
                    MACK_LOW: begin sda_low<=bytes_left>1;state<=MACK_HIGH;end
                    MACK_HIGH: begin scl_low<=0;if(scl_sync2) state<=MACK_HOLD;end
                    MACK_HOLD: state<=MACK_FALL;
                    MACK_FALL: begin
                        scl_low<=1;sda_low<=0;read_data<={read_data[39:0],rx};
                        bytes_left<=bytes_left-1'b1;
                        if(bytes_left>1) begin bit_index<=7;rx<=0;state<=RX_LOW;end
                        else state<=STOP_LOW;
                    end
                    STOP_LOW: begin scl_low<=1;sda_low<=1;state<=STOP_HIGH;end
                    STOP_HIGH: begin scl_low<=0;if(scl_sync2) state<=STOP_SDA;end
                    STOP_SDA: begin sda_low<=0;state<=STOP_DONE;end
                    STOP_DONE: begin busy<=0;done<=1;state<=IDLE;end
                    default: begin error<=1;state<=STOP_LOW;end
                endcase
            end
        end
    end
endmodule
