// Dynamic cells and colors for the pre-rendered System Health panel.
// FIFO values are hexadecimal; N/A means no fresh sample in the active epoch.
module m9_health_panel_formatter (
    input wire [1:0] health_status,input wire [2:0] pll_status,
    input wire [1:0] init_status,input wire [1:0] heartbeat_status,
    input wire [9:0] read_level,input wire [8:0] write_level,input wire [8:0] pcm_level,
    input wire [2:0] snapshot_valid,input wire [2:0] expected,
    input wire [2:0] fifo_warning,input wire [3:0] media_state,
    input wire [1:0] failsafe_state,input wire [7:0] last_error_code,
    input wire [2:0] last_media_error_stage,input wire [7:0] last_media_error_code,
    input wire [15:0] error_count,input wire [7:0] degraded_reason,
    input wire [3:0] color_class,input wire [5:0] slot_id,
    output reg [7:0] char_code,output reg dynamic_position,
    output reg [2:0] color_role
);
    localparam [2:0] COLOR_NORMAL=3'd0,COLOR_HEADER=3'd1;
    localparam [2:0] COLOR_HEALTHY=3'd2,COLOR_DEGRADED=3'd3;
    localparam [2:0] COLOR_FAULT=3'd4,COLOR_MUTED=3'd5;
    wire read_value_valid=expected[2] && snapshot_valid[2];
    wire write_value_valid=expected[1] && snapshot_valid[1];
    wire pcm_value_valid=expected[0] && snapshot_valid[0];
    function [7:0] hex_char;input [3:0] value;begin
        hex_char=value<10 ? "0"+value : "A"+(value-10);
    end endfunction
    function [7:0] bit_char;input value;begin bit_char=value ? "1" : "0";end endfunction
    function [7:0] status_char;input [1:0] status;input [5:0] slot;begin
        status_char=" ";
        case(status)
            2'd0:case(slot)
                1:status_char="H";2:status_char="E";3:status_char="A";4:status_char="L";
                5:status_char="T";6:status_char="H";7:status_char="Y";
            endcase
            2'd1:case(slot)
                1:status_char="D";2:status_char="E";3:status_char="G";4:status_char="R";
                5:status_char="A";6:status_char="D";7:status_char="E";8:status_char="D";
            endcase
            default:case(slot)
                1:status_char="F";2:status_char="A";3:status_char="U";4:status_char="L";5:status_char="T";
            endcase
        endcase
    end endfunction
    always @(*) begin
        char_code=" ";dynamic_position=slot_id!=0;
        case(slot_id)
            1,2,3,4,5,6,7,8:char_code=status_char(health_status,slot_id);
            9:char_code=bit_char(pll_status[0]);
            10:char_code=bit_char(pll_status[1]);
            11:char_code=bit_char(pll_status[2]);
            12:char_code=bit_char(init_status[0]);
            13:char_code=bit_char(init_status[1]);
            14:char_code=bit_char(heartbeat_status[0]);
            15:char_code=bit_char(heartbeat_status[1]);
            16:char_code=read_value_valid ? hex_char({2'b00,read_level[9:8]}) : "N";
            17:char_code=read_value_valid ? hex_char(read_level[7:4]) : "/";
            18:char_code=read_value_valid ? hex_char(read_level[3:0]) : "A";
            19:char_code=bit_char(snapshot_valid[2]);
            20:char_code=bit_char(expected[2]);
            21:char_code=write_value_valid ? hex_char({3'b000,write_level[8]}) : "N";
            22:char_code=write_value_valid ? hex_char(write_level[7:4]) : "/";
            23:char_code=write_value_valid ? hex_char(write_level[3:0]) : "A";
            24:char_code=bit_char(snapshot_valid[1]);
            25:char_code=bit_char(expected[1]);
            26:char_code=pcm_value_valid ? hex_char({3'b000,pcm_level[8]}) : "N";
            27:char_code=pcm_value_valid ? hex_char(pcm_level[7:4]) : "/";
            28:char_code=pcm_value_valid ? hex_char(pcm_level[3:0]) : "A";
            29:char_code=bit_char(snapshot_valid[0]);
            30:char_code=bit_char(expected[0]);
            31:char_code=bit_char(fifo_warning[2]);
            32:char_code=bit_char(fifo_warning[1]);
            33:char_code=bit_char(fifo_warning[0]);
            34:char_code=hex_char(media_state);
            35:char_code=hex_char({2'b00,failsafe_state});
            36:char_code=hex_char(last_error_code[7:4]);
            37:char_code=hex_char(last_error_code[3:0]);
            38:char_code=hex_char(error_count[15:12]);
            39:char_code=hex_char(error_count[11:8]);
            40:char_code=hex_char(error_count[7:4]);
            41:char_code=hex_char(error_count[3:0]);
            42:char_code=hex_char({1'b0,last_media_error_stage});
            43:char_code=hex_char(last_media_error_code[7:4]);
            44:char_code=hex_char(last_media_error_code[3:0]);
            45:char_code=bit_char(degraded_reason[7]);
            46:char_code=bit_char(degraded_reason[6]);
            47:char_code=bit_char(degraded_reason[5]);
            48:char_code=bit_char(degraded_reason[4]);
            49:char_code=bit_char(degraded_reason[3]);
            50:char_code=bit_char(degraded_reason[2]);
            51:char_code=bit_char(degraded_reason[1]);
            52:char_code=bit_char(degraded_reason[0]);
            default:char_code=" ";
        endcase
    end
    always @(*) begin
        color_role=COLOR_NORMAL;
        case(color_class)
            1:color_role=COLOR_HEADER;
            2:color_role=health_status==0 ? COLOR_HEALTHY :
                         (health_status==1 ? COLOR_DEGRADED : COLOR_FAULT);
            3:color_role=read_value_valid ? COLOR_NORMAL : COLOR_MUTED;
            4:color_role=write_value_valid ? COLOR_NORMAL : COLOR_MUTED;
            5:color_role=pcm_value_valid ? COLOR_NORMAL : COLOR_MUTED;
            6:color_role=|fifo_warning ? COLOR_DEGRADED : COLOR_MUTED;
            7:color_role=last_error_code!=0 ? COLOR_FAULT : COLOR_MUTED;
            8:color_role=last_media_error_code!=0 ? COLOR_FAULT : COLOR_MUTED;
            9:color_role=degraded_reason!=0 ? COLOR_DEGRADED : COLOR_MUTED;
            10:color_role=COLOR_MUTED;
            default:color_role=COLOR_NORMAL;
        endcase
    end
endmodule
