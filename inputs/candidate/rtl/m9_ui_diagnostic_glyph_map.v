// D1-DIAG-LITE: only true summary, latched fault, failsafe and media error.
// Removed telemetry never participates in the dynamic Glyph ROM address.
module m9_ui_diagnostic_glyph_map (
    input wire [90:0] health_data,input wire received,input wire [5:0] slot_id,
    output wire [7:0] glyph_id,output wire glyph_half,output wire [2:0] color_role
);
    localparam [7:0] BLANK=0,QUESTION=1,SLASH=2;
    localparam [7:0] A=13,B=14,C=15,D=16,E=17,F=18,G=19,I=21;
    localparam [7:0] L=24,M=25,N=26,O=27,P=28,R=30,S=31,T=32,U=33,V=34;
    localparam [2:0] ROLE_NORMAL=0,ROLE_GOOD=2,ROLE_WARNING=3;
    localparam [2:0] ROLE_FAULT=4,ROLE_MUTED=5;
    localparam [3:0] WORD_PREPARING=0,WORD_SAFE=1,WORD_RECOVER=2;
    localparam [3:0] WORD_FAULT=3,WORD_DEGRADED=4,WORD_NORMAL=5;
    localparam [3:0] WORD_NA=6,WORD_NONE=7,WORD_BOOT=8,WORD_UNKNOWN=9;
    localparam [1:0] MODE_NA=0,MODE_NONE=1,MODE_VALUE=2,MODE_UNKNOWN=3;

    function [7:0] hex_glyph;
        input [3:0] nibble;
        begin
            case(nibble)
                0:hex_glyph=3;1:hex_glyph=4;2:hex_glyph=5;3:hex_glyph=6;
                4:hex_glyph=7;5:hex_glyph=8;6:hex_glyph=9;7:hex_glyph=10;
                8:hex_glyph=11;9:hex_glyph=12;10:hex_glyph=13;11:hex_glyph=14;
                12:hex_glyph=15;13:hex_glyph=16;14:hex_glyph=17;15:hex_glyph=18;
                default:hex_glyph=QUESTION;
            endcase
        end
    endfunction

    function [7:0] word_glyph;
        input [3:0] word_id;
        input [3:0] position;
        begin
            word_glyph=BLANK;
            case({word_id,position})
                {WORD_PREPARING,4'd0}:word_glyph=8'd51;
                {WORD_PREPARING,4'd1}:word_glyph=8'd51;
                {WORD_PREPARING,4'd2}:word_glyph=8'd61;
                {WORD_PREPARING,4'd3}:word_glyph=8'd61;
                {WORD_PREPARING,4'd4}:word_glyph=8'd41;
                {WORD_PREPARING,4'd5}:word_glyph=8'd41;
                {WORD_SAFE,4'd0}:word_glyph=8'd66;
                {WORD_SAFE,4'd1}:word_glyph=8'd66;
                {WORD_SAFE,4'd2}:word_glyph=8'd50;
                {WORD_SAFE,4'd3}:word_glyph=8'd50;
                {WORD_RECOVER,4'd0}:word_glyph=8'd77;
                {WORD_RECOVER,4'd1}:word_glyph=8'd77;
                {WORD_RECOVER,4'd2}:word_glyph=8'd62;
                {WORD_RECOVER,4'd3}:word_glyph=8'd62;
                {WORD_RECOVER,4'd4}:word_glyph=8'd41;
                {WORD_RECOVER,4'd5}:word_glyph=8'd41;
                {WORD_FAULT,4'd0}:word_glyph=8'd80;
                {WORD_FAULT,4'd1}:word_glyph=8'd80;
                {WORD_FAULT,4'd2}:word_glyph=8'd118;
                {WORD_FAULT,4'd3}:word_glyph=8'd118;
                {WORD_DEGRADED,4'd0}:word_glyph=8'd117;
                {WORD_DEGRADED,4'd1}:word_glyph=8'd117;
                {WORD_DEGRADED,4'd2}:word_glyph=8'd104;
                {WORD_DEGRADED,4'd3}:word_glyph=8'd104;
                {WORD_NORMAL,4'd0}:word_glyph=8'd90;
                {WORD_NORMAL,4'd1}:word_glyph=8'd90;
                {WORD_NORMAL,4'd2}:word_glyph=8'd70;
                {WORD_NORMAL,4'd3}:word_glyph=8'd70;
                {WORD_NA,4'd0}:word_glyph=8'd40;
                {WORD_NA,4'd1}:word_glyph=8'd40;
                {WORD_NA,4'd2}:word_glyph=8'd113;
                {WORD_NA,4'd3}:word_glyph=8'd113;
                {WORD_NA,4'd4}:word_glyph=8'd98;
                {WORD_NA,4'd5}:word_glyph=8'd98;
                {WORD_NONE,4'd0}:word_glyph=8'd82;
                {WORD_NONE,4'd1}:word_glyph=8'd82;
                {WORD_BOOT,4'd0}:word_glyph=8'd56;
                {WORD_BOOT,4'd1}:word_glyph=8'd56;
                {WORD_BOOT,4'd2}:word_glyph=8'd54;
                {WORD_BOOT,4'd3}:word_glyph=8'd54;
                {WORD_BOOT,4'd4}:word_glyph=8'd41;
                {WORD_BOOT,4'd5}:word_glyph=8'd41;
                {WORD_UNKNOWN,4'd0}:word_glyph=8'd1;
            endcase
        end
    endfunction

    function word_half;
        input [3:0] word_id;
        input [3:0] position;
        begin
            case(word_id)
                WORD_UNKNOWN:word_half=1'b0;
                default:word_half=position[0];
            endcase
        end
    endfunction

    function [3:0] system_word;
        input seen;
        input [1:0] failsafe;
        input [1:0] status;
        begin
            system_word=WORD_PREPARING;
            case(seen)
                1'b1:case(status)
                    2'd0,2'd1,2'd2:case(failsafe)
                        2'd2:system_word=WORD_SAFE;
                        2'd3:system_word=WORD_RECOVER;
                        2'd0,2'd1:case(status)
                            2'd0:system_word=WORD_NORMAL;
                            2'd1:system_word=WORD_DEGRADED;
                            default:system_word=WORD_FAULT;
                        endcase
                        default:system_word=WORD_UNKNOWN;
                    endcase
                    default:system_word=WORD_UNKNOWN;
                endcase
                default:system_word=WORD_PREPARING;
            endcase
        end
    endfunction

    function [3:0] failsafe_word;
        input seen;
        input [1:0] state;
        begin
            failsafe_word=WORD_NA;
            case(seen)
                1'b1:case(state)
                    2'd0:failsafe_word=WORD_BOOT;
                    2'd1:failsafe_word=WORD_NORMAL;
                    2'd2:failsafe_word=WORD_SAFE;
                    2'd3:failsafe_word=WORD_RECOVER;
                    default:failsafe_word=WORD_UNKNOWN;
                endcase
                default:failsafe_word=WORD_NA;
            endcase
        end
    endfunction

    function [1:0] fault_mode;
        input seen;
        input [7:0] value;
        begin
            fault_mode=MODE_NA;
            case(seen)
                1'b1:case(value)
                    8'h00:fault_mode=MODE_NONE;
                    8'h90,8'h91,8'h92,8'h93,8'h94,8'h95,
                    8'h96,8'h97,8'h98,8'h99,8'h9a:fault_mode=MODE_VALUE;
                    default:fault_mode=MODE_UNKNOWN;
                endcase
                default:fault_mode=MODE_NA;
            endcase
        end
    endfunction

    function [1:0] media_mode;
        input seen;
        input [7:0] fault;
        input [2:0] stage_value;
        input [7:0] detail;
        begin
            media_mode=MODE_NA;
            case(seen)
                1'b1:case(^fault)
                    1'b0,1'b1:case(fault)
                        8'h99:case(stage_value)
                            3'd5:case(^detail)
                                1'b0,1'b1:case(detail)
                                    8'h01,8'h02,8'h03,8'h04,8'h05,8'h06,
                                    8'h07,8'h08,8'h09,8'h0a,8'h0b,8'h0c:
                                        media_mode=MODE_VALUE;
                                    default:media_mode=MODE_NA;
                                endcase
                                default:media_mode=MODE_UNKNOWN;
                            endcase
                            3'd1,3'd2,3'd3,3'd4,3'd6:case(^detail)
                                1'b0,1'b1:media_mode=detail==0 ? MODE_NA : MODE_VALUE;
                                default:media_mode=MODE_UNKNOWN;
                            endcase
                            3'd0,3'd7:media_mode=MODE_NA;
                            default:media_mode=MODE_UNKNOWN;
                        endcase
                        default:media_mode=MODE_NA;
                    endcase
                    default:media_mode=MODE_UNKNOWN;
                endcase
                default:media_mode=MODE_NA;
            endcase
        end
    endfunction

    function [7:0] fault_glyph;
        input [1:0] mode;
        input [3:0] position;
        input [7:0] value;
        begin
            fault_glyph=BLANK;
            case(mode)
                MODE_NA:fault_glyph=word_glyph(WORD_NA,position);
                MODE_NONE:fault_glyph=word_glyph(WORD_NONE,position);
                MODE_UNKNOWN:fault_glyph=word_glyph(WORD_UNKNOWN,position);
                default:case(position)
                    0:fault_glyph=E;
                    1:fault_glyph=hex_glyph(value[7:4]);
                    2:fault_glyph=hex_glyph(value[3:0]);
                    default:fault_glyph=BLANK;
                endcase
            endcase
        end
    endfunction


    function fault_half;
        input [1:0] mode;
        input [3:0] position;
        begin
            case(mode)
                MODE_NA:fault_half=word_half(WORD_NA,position);
                MODE_NONE:fault_half=word_half(WORD_NONE,position);
                default:fault_half=1'b0;
            endcase
        end
    endfunction

    function media_half;
        input [1:0] mode;
        input [3:0] position;
        begin
            media_half=mode==MODE_NA ? word_half(WORD_NA,position) : 1'b0;
        end
    endfunction

    function [7:0] media_stage_glyph;
        input [1:0] mode;
        input [3:0] position;
        input [2:0] value;
        begin
            media_stage_glyph=BLANK;
            case(mode)
                MODE_NA:media_stage_glyph=word_glyph(WORD_NA,position);
                MODE_UNKNOWN:media_stage_glyph=word_glyph(WORD_UNKNOWN,position);
                default:if(position==0)media_stage_glyph=hex_glyph({1'b0,value});
            endcase
        end
    endfunction

    function [7:0] media_code_glyph;
        input [1:0] mode;
        input [3:0] position;
        input [7:0] value;
        begin
            media_code_glyph=BLANK;
            case(mode)
                MODE_NA:media_code_glyph=word_glyph(WORD_NA,position);
                MODE_UNKNOWN:media_code_glyph=word_glyph(WORD_UNKNOWN,position);
                default:case(position)
                    0:media_code_glyph=hex_glyph(value[7:4]);
                    1:media_code_glyph=hex_glyph(value[3:0]);
                    default:media_code_glyph=BLANK;
                endcase
            endcase
        end
    endfunction

    wire [3:0] system_value=system_word(received,health_data[90:89],health_data[88:87]);
    wire [3:0] failsafe_value=failsafe_word(received,health_data[90:89]);
    wire [1:0] fault_value=fault_mode(received,health_data[86:79]);
    wire [1:0] media_value=media_mode(received,health_data[86:79],
        health_data[34:32],health_data[31:24]);
    reg [7:0] glyph_result;
    reg [2:0] role_result;
    reg half_result;

    always @(*) begin
        glyph_result=BLANK;
        role_result=ROLE_NORMAL;
        case(slot_id)
            1:glyph_result=word_glyph(system_value,4'd0);
            2:glyph_result=word_glyph(system_value,4'd1);
            3:glyph_result=word_glyph(system_value,4'd2);
            4:glyph_result=word_glyph(system_value,4'd3);
            5:glyph_result=word_glyph(system_value,4'd4);
            6:glyph_result=word_glyph(system_value,4'd5);
            7:glyph_result=word_glyph(system_value,4'd6);
            8:glyph_result=word_glyph(system_value,4'd7);
            9:glyph_result=word_glyph(system_value,4'd8);
            10:glyph_result=fault_glyph(fault_value,4'd0,health_data[86:79]);
            11:glyph_result=fault_glyph(fault_value,4'd1,health_data[86:79]);
            12:glyph_result=fault_glyph(fault_value,4'd2,health_data[86:79]);
            13:glyph_result=fault_glyph(fault_value,4'd3,health_data[86:79]);
            14:glyph_result=fault_glyph(fault_value,4'd4,health_data[86:79]);
            15:glyph_result=fault_glyph(fault_value,4'd5,health_data[86:79]);
            16:glyph_result=word_glyph(failsafe_value,4'd0);
            17:glyph_result=word_glyph(failsafe_value,4'd1);
            18:glyph_result=word_glyph(failsafe_value,4'd2);
            19:glyph_result=word_glyph(failsafe_value,4'd3);
            20:glyph_result=word_glyph(failsafe_value,4'd4);
            21:glyph_result=word_glyph(failsafe_value,4'd5);
            22:glyph_result=word_glyph(failsafe_value,4'd6);
            23:glyph_result=media_stage_glyph(media_value,4'd0,health_data[34:32]);
            24:glyph_result=media_stage_glyph(media_value,4'd1,health_data[34:32]);
            25:glyph_result=media_stage_glyph(media_value,4'd2,health_data[34:32]);
            26:glyph_result=media_stage_glyph(media_value,4'd3,health_data[34:32]);
            27:glyph_result=media_stage_glyph(media_value,4'd4,health_data[34:32]);
            28:glyph_result=media_stage_glyph(media_value,4'd5,health_data[34:32]);
            29:glyph_result=media_code_glyph(media_value,4'd0,health_data[31:24]);
            30:glyph_result=media_code_glyph(media_value,4'd1,health_data[31:24]);
            31:glyph_result=media_code_glyph(media_value,4'd2,health_data[31:24]);
            32:glyph_result=media_code_glyph(media_value,4'd3,health_data[31:24]);
            33:glyph_result=media_code_glyph(media_value,4'd4,health_data[31:24]);
            34:glyph_result=media_code_glyph(media_value,4'd5,health_data[31:24]);
            default:begin end
        endcase
        case(slot_id)
            1,2,3,4,5,6,7,8,9:case(system_value)
                WORD_NORMAL:role_result=ROLE_GOOD;
                WORD_DEGRADED,WORD_RECOVER:role_result=ROLE_WARNING;
                WORD_SAFE,WORD_FAULT,WORD_UNKNOWN:role_result=ROLE_FAULT;
                default:role_result=ROLE_MUTED;
            endcase
            10,11,12,13,14,15:role_result=(fault_value==MODE_VALUE ||
                fault_value==MODE_UNKNOWN) ? ROLE_FAULT : ROLE_MUTED;
            16,17,18,19,20,21,22:case(failsafe_value)
                WORD_NORMAL:role_result=ROLE_GOOD;
                WORD_RECOVER:role_result=ROLE_WARNING;
                WORD_SAFE,WORD_UNKNOWN:role_result=ROLE_FAULT;
                default:role_result=ROLE_MUTED;
            endcase
            23,24,25,26,27,28,29,30,31,32,33,34:role_result=(media_value==MODE_VALUE ||
                media_value==MODE_UNKNOWN) ? ROLE_FAULT : ROLE_MUTED;
            default:role_result=ROLE_NORMAL;
        endcase
    end

    always @(*) begin
        half_result=1'b0;
        case(slot_id)
            1:half_result=word_half(system_value,4'd0);
            2:half_result=word_half(system_value,4'd1);
            3:half_result=word_half(system_value,4'd2);
            4:half_result=word_half(system_value,4'd3);
            5:half_result=word_half(system_value,4'd4);
            6:half_result=word_half(system_value,4'd5);
            7:half_result=word_half(system_value,4'd6);
            8:half_result=word_half(system_value,4'd7);
            9:half_result=word_half(system_value,4'd8);
            10:half_result=fault_half(fault_value,4'd0);
            11:half_result=fault_half(fault_value,4'd1);
            12:half_result=fault_half(fault_value,4'd2);
            13:half_result=fault_half(fault_value,4'd3);
            14:half_result=fault_half(fault_value,4'd4);
            15:half_result=fault_half(fault_value,4'd5);
            16:half_result=word_half(failsafe_value,4'd0);
            17:half_result=word_half(failsafe_value,4'd1);
            18:half_result=word_half(failsafe_value,4'd2);
            19:half_result=word_half(failsafe_value,4'd3);
            20:half_result=word_half(failsafe_value,4'd4);
            21:half_result=word_half(failsafe_value,4'd5);
            22:half_result=word_half(failsafe_value,4'd6);
            23:half_result=media_half(media_value,4'd0);
            24:half_result=media_half(media_value,4'd1);
            25:half_result=media_half(media_value,4'd2);
            26:half_result=media_half(media_value,4'd3);
            27:half_result=media_half(media_value,4'd4);
            28:half_result=media_half(media_value,4'd5);
            29:half_result=media_half(media_value,4'd0);
            30:half_result=media_half(media_value,4'd1);
            31:half_result=media_half(media_value,4'd2);
            32:half_result=media_half(media_value,4'd3);
            33:half_result=media_half(media_value,4'd4);
            34:half_result=media_half(media_value,4'd5);
            default:begin end
        endcase
    end
    assign glyph_id=glyph_result;
    assign glyph_half=half_result;
    assign color_role=role_result;
endmodule
