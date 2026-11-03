`timescale 1ns/1ps
// MAX30102/MAX30105 red+IR mode, 100 samples/s, 18-bit, FIFO polling.
module m9_max3010x_acquisition #(
    parameter integer QUARTER_CYCLES=63,
    parameter integer BUS_TIMEOUT_CYCLES=500000,
    parameter integer RESET_WAIT_CYCLES=1000000,
    parameter integer POLL_CYCLES=200000,
    parameter integer RETRY_CYCLES=10000000,
    parameter [7:0] RED_LED_CURRENT=8'h24, IR_LED_CURRENT=8'h24
)(
    input wire clk,input wire rst,inout wire scl,inout wire sda,
    input wire sample_ready,output reg sample_valid,
    output reg [17:0] red_sample,output reg [17:0] ir_sample,
    output reg sample_gap,output reg sensor_ready,output reg [7:0] fault_code
);
    reg request,read_mode;
    reg [7:0] register_address,write_data;
    reg [3:0] read_count;
    wire busy,done,error;
    wire [47:0] read_data;
    m9_i2c_register_master #(.QUARTER_CYCLES(QUARTER_CYCLES),.TIMEOUT_CYCLES(BUS_TIMEOUT_CYCLES)) u_bus(
        .clk(clk),.rst(rst),.request(request),.read_not_write(read_mode),.device_address(7'h57),
        .register_address(register_address),.write_data(write_data),.read_count(read_count),
        .scl(scl),.sda(sda),.busy(busy),.done(done),.error(error),.read_data(read_data));
    localparam RESET_SEND=0,RESET_ACK=1,RESET_DELAY=2,RESET_POLL_SEND=3,RESET_POLL_ACK=4,
        ID_SEND=5,ID_ACK=6,CONFIG_SEND=7,CONFIG_ACK=8,POLL_DELAY=9,
        POINTER_SEND=10,POINTER_ACK=11,FIFO_SEND=12,FIFO_ACK=13,DELIVER=14,RETRY=15;
    reg [4:0] state;
    reg [3:0] config_index;
    reg [4:0] reset_attempts;
    reg [31:0] timer;
    function [7:0] config_register;
        input [3:0] index;
        begin
            case(index)
                0:config_register=8'h04;1:config_register=8'h05;2:config_register=8'h06;
                3:config_register=8'h08;4:config_register=8'h0a;5:config_register=8'h0c;
                6:config_register=8'h0d;default:config_register=8'h09;
            endcase
        end
    endfunction
    function [7:0] config_value;
        input [3:0] index;
        begin
            case(index)
                4:config_value=8'h27;5:config_value=RED_LED_CURRENT;
                6:config_value=IR_LED_CURRENT;7:config_value=8'h03;
                default:config_value=0;
            endcase
        end
    endfunction
    task fail;
        input [7:0] code;
        begin
            sensor_ready<=0;sample_valid<=0;sample_gap<=1;fault_code<=code;
            timer<=0;state<=RETRY;
        end
    endtask
    always @(posedge clk) begin
        if(rst) begin
            request<=0;read_mode<=0;register_address<=0;write_data<=0;read_count<=1;
            state<=RESET_SEND;config_index<=0;reset_attempts<=0;timer<=0;
            sample_valid<=0;red_sample<=0;ir_sample<=0;sample_gap<=0;sensor_ready<=0;fault_code<=0;
        end else begin
            request<=0;sample_gap<=0;
            if(sample_valid && sample_ready) sample_valid<=0;
            case(state)
                RESET_SEND: if(!busy) begin
                    register_address<=8'h09;write_data<=8'h40;read_mode<=0;request<=1;state<=RESET_ACK;
                end
                RESET_ACK: if(done) begin
                    if(error) fail(8'h01);else begin timer<=0;state<=RESET_DELAY;end
                end
                RESET_DELAY: if(timer>=RESET_WAIT_CYCLES-1) begin timer<=0;state<=RESET_POLL_SEND;end
                    else timer<=timer+1'b1;
                RESET_POLL_SEND: if(!busy) begin
                    register_address<=8'h09;read_mode<=1;read_count<=1;request<=1;state<=RESET_POLL_ACK;
                end
                RESET_POLL_ACK: if(done) begin
                    if(error) fail(8'h01);
                    else if(read_data[6] && reset_attempts==19) fail(8'h02);
                    else if(read_data[6]) begin reset_attempts<=reset_attempts+1'b1;timer<=0;state<=RESET_DELAY;end
                    else state<=ID_SEND;
                end
                ID_SEND: if(!busy) begin
                    register_address<=8'hff;read_mode<=1;read_count<=1;request<=1;state<=ID_ACK;
                end
                ID_ACK: if(done) begin
                    if(error) fail(8'h01);
                    else if(read_data[7:0]!=8'h15) fail(8'h03);
                    else begin config_index<=0;state<=CONFIG_SEND;end
                end
                CONFIG_SEND: if(!busy) begin
                    register_address<=config_register(config_index);write_data<=config_value(config_index);
                    read_mode<=0;request<=1;state<=CONFIG_ACK;
                end
                CONFIG_ACK: if(done) begin
                    if(error) fail(8'h01);
                    else if(config_index==7) begin sensor_ready<=1;fault_code<=0;timer<=0;state<=POLL_DELAY;end
                    else begin config_index<=config_index+1'b1;state<=CONFIG_SEND;end
                end
                POLL_DELAY: if(timer>=POLL_CYCLES-1) begin timer<=0;state<=POINTER_SEND;end
                    else timer<=timer+1'b1;
                POINTER_SEND: if(!busy) begin
                    register_address<=8'h04;read_mode<=1;read_count<=3;request<=1;state<=POINTER_ACK;
                end
                POINTER_ACK: if(done) begin
                    if(error) fail(8'h01);
                    else if(read_data[12:8]!=0) fail(8'h04);
                    else if(read_data[20:16]!=read_data[4:0]) state<=FIFO_SEND;
                    else begin timer<=0;state<=POLL_DELAY;end
                end
                FIFO_SEND: if(!busy) begin
                    register_address<=8'h07;read_mode<=1;read_count<=6;request<=1;state<=FIFO_ACK;
                end
                FIFO_ACK: if(done) begin
                    if(error) fail(8'h01);
                    else begin
                        red_sample<=read_data[41:24];ir_sample<=read_data[17:0];sample_valid<=1;state<=DELIVER;
                    end
                end
                DELIVER: if(sample_valid && sample_ready) state<=POINTER_SEND;
                RETRY: if(timer>=RETRY_CYCLES-1) begin
                    timer<=0;reset_attempts<=0;state<=RESET_SEND;
                end else timer<=timer+1'b1;
                default: fail(8'hff);
            endcase
        end
    end
endmodule
