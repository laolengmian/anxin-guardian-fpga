`timescale 1ns/1ps

// M9 private FAT32 scanner. One root-directory traversal builds both the
// PIC1.BMP..PIC4.BMP and PIC1.WAV..PIC4.WAV catalogs. MBR/BPB fields are
// captured as bytes arrive; no complete 512-byte metadata sector is stored.
module m9_fat32_media_catalog #(
    parameter integer MAX_ROOT_CLUSTERS=8192
) (
    input wire clk,input wire rst_n,input wire scan_start,
    output wire scan_busy,output reg scan_done,output reg [7:0] fs_error,
    output reg [7:0] image_catalog_error,output reg [7:0] audio_catalog_error,
    output reg [31:0] partition_lba,output reg [7:0] sectors_per_cluster,
    output reg [31:0] fat_start_lba,output reg [31:0] data_start_lba,
    output reg [31:0] max_cluster,
    output reg [3:0] image_valid,output reg [3:0] audio_valid,
    input wire catalog_select_audio,input wire [1:0] catalog_select_index,
    output wire catalog_entry_valid,
    output wire [31:0] catalog_entry_cluster,
    output wire [31:0] catalog_entry_size,
    output reg sector_req,output reg [31:0] sector_lba,
    input wire sector_busy,input wire sector_valid,input wire [7:0] sector_byte,
    input wire [8:0] sector_byte_index,input wire sector_done,
    input wire [7:0] sector_error,output wire sector_ready
);
    localparam [7:0] ERR_NONE=8'h00,ERR_SECTOR=8'h10;
    localparam [7:0] ERR_BOOT_SIGNATURE=8'h20,ERR_UNSUPPORTED_BPB=8'h21;
    localparam [7:0] ERR_RESOURCE_MISSING=8'h22,ERR_ROOT_CHAIN=8'h23;
    localparam [7:0] ERR_ROOT_LOOP=8'h24,ERR_ROOT_VISITED=8'h25;
    localparam [7:0] ERR_DIRECTORY_ENTRY=8'h26;

    localparam [4:0] ST_IDLE=5'd0,ST_READ0_REQ=5'd1,ST_READ0_WAIT=5'd2;
    localparam [4:0] ST_BOOT_REQ=5'd3,ST_BOOT_WAIT=5'd4,ST_BOOT_PARSE=5'd5;
    localparam [4:0] ST_LAYOUT=5'd6,ST_ROOT_INIT=5'd7,ST_ROOT_REQ=5'd8;
    localparam [4:0] ST_ROOT_WAIT=5'd9,ST_FAT_REQ=5'd10,ST_FAT_WAIT=5'd11;
    localparam [4:0] ST_FAT_PARSE=5'd12,ST_FINISH=5'd13,ST_LAYOUT2=5'd14;
    localparam [4:0] ST_LAYOUT3=5'd15,ST_LAYOUT4=5'd16;
    localparam [4:0] ST_ROOT_LBA1=5'd17,ST_ROOT_LBA2=5'd18;
    localparam [4:0] ST_BOOT_COMMIT=5'd19,ST_LAYOUT5=5'd20;
    localparam integer ROOT_COUNT_WIDTH=
        (MAX_ROOT_CLUSTERS<=1) ? 1 : $clog2(MAX_ROOT_CLUSTERS+1);

    reg [4:0] state;
    reg [7:0] first_sector_byte,partition_type;
    reg [31:0] mbr_partition_lba,mbr_partition_sectors;
    reg [31:0] candidate_partition_lba;
    reg [15:0] boot_signature;
    reg [15:0] bpb_bytes_per_sector,bpb_reserved_sectors;
    reg [15:0] bpb_root_entry_count,bpb_fat16_sectors;
    reg [7:0] bpb_sectors_per_cluster,bpb_fat_count;
    reg [31:0] bpb_total_sectors,bpb_fat_sectors,bpb_root_cluster;

    reg [31:0] total_sectors,fat_sectors,fat_span,data_sector_count;
    reg [31:0] root_cluster,current_root_cluster;
    reg [7:0] root_sector_index,fat_count;
    reg [2:0] sectors_per_cluster_shift;
    reg [15:0] reserved_sectors;
    reg [ROOT_COUNT_WIDTH-1:0] root_cluster_count;
    reg [31:0] layout_offset,max_cluster_pre,lba_base,root_shifted;
    reg [2:0] candidate_sectors_per_cluster_shift;
    reg [32:0] candidate_fat_span_wide;
    reg [33:0] candidate_layout_offset_wide;
    reg [32:0] candidate_data_sector_count_wide;
    reg [32:0] candidate_max_cluster_pre_wide;
    reg [32:0] candidate_max_cluster_wide;
    reg [32:0] candidate_fat_start_lba_wide;
    reg [32:0] candidate_data_start_lba_wide;
    reg [32:0] candidate_volume_end_lba_wide;
    reg [31:0] candidate_lba_base;
    reg candidate_partition_bounds_bad /* fehdl keep="true" */;
    reg candidate_fat_capacity_bad /* fehdl keep="true" */;

    reg root_end_seen,image_directory_fault,audio_directory_fault;
    reg metadata_capture_q /* fehdl keep="true" */;
    reg metadata_clear_q /* fehdl keep="true" */;
    reg entry_name_match,entry_image_match,entry_audio_match;
    reg entry_candidate,entry_is_audio,entry_cluster_bad,size_zero_low16;
    reg [1:0] entry_resource;
    reg [15:0] entry_cluster_high,entry_cluster_low;
    reg [31:0] entry_size;

    reg [8:0] fat_entry_offset;
    reg [7:0] fat_byte0,fat_byte1,fat_byte2,fat_byte3;

    reg [63:0] catalog_mem [0:7] /* fehdl force_ram=1, ram_style="bram" */;
    reg catalog_write_enable;
    reg [2:0] catalog_write_address;
    reg [63:0] catalog_write_data;
    reg [63:0] catalog_entry_q;
    wire [27:0] next_root_cluster={fat_byte3[3:0],fat_byte2,fat_byte1,fat_byte0};
    wire catalogs_complete=image_valid==4'hf && audio_valid==4'hf;

    assign scan_busy=state!=ST_IDLE;
    assign sector_ready=1'b1;
    assign catalog_entry_valid=catalog_select_audio ?
                               audio_valid[catalog_select_index] :
                               image_valid[catalog_select_index];
    assign catalog_entry_cluster=catalog_entry_q[63:32];
    assign catalog_entry_size=catalog_entry_q[31:0];

    always @(posedge clk) begin
        catalog_entry_q<=catalog_mem[{catalog_select_audio,catalog_select_index}];
        if(catalog_write_enable)
            catalog_mem[catalog_write_address]<=catalog_write_data;
    end

    function valid_spc;
        input [7:0] value;
        begin
            case(value)
                8'd1,8'd2,8'd4,8'd8,8'd16,8'd32,8'd64,8'd128:
                    valid_spc=1'b1;
                default:valid_spc=1'b0;
            endcase
        end
    endfunction

    function [2:0] spc_shift;
        input [7:0] value;
        begin
            case(value)
                8'd1:spc_shift=3'd0;8'd2:spc_shift=3'd1;
                8'd4:spc_shift=3'd2;8'd8:spc_shift=3'd3;
                8'd16:spc_shift=3'd4;8'd32:spc_shift=3'd5;
                8'd64:spc_shift=3'd6;8'd128:spc_shift=3'd7;
                default:spc_shift=3'd0;
            endcase
        end
    endfunction

    task finish_with_error;
        input [7:0] code;
        begin
            fs_error<=code;
            image_catalog_error<=code;
            audio_catalog_error<=code;
            state<=ST_FINISH;
        end
    endtask

    task accept_entry;
        begin
            if(entry_cluster_bad ||
               (size_zero_low16 && entry_size[23:16]==8'd0 && sector_byte==8'd0)) begin
                if(entry_is_audio) audio_directory_fault<=1'b1;
                else image_directory_fault<=1'b1;
            end else if(entry_is_audio) begin
                if(!audio_valid[entry_resource]) begin
                    catalog_write_enable<=1'b1;
                    catalog_write_address<={1'b1,entry_resource};

                    audio_valid[entry_resource]<=1'b1;
                end
            end else if(!image_valid[entry_resource]) begin
                catalog_write_enable<=1'b1;
                catalog_write_address<={1'b0,entry_resource};

                image_valid[entry_resource]<=1'b1;
            end
        end
    endtask

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state<=ST_IDLE;scan_done<=0;fs_error<=ERR_NONE;
            image_catalog_error<=ERR_NONE;audio_catalog_error<=ERR_NONE;
            partition_lba<=0;sectors_per_cluster<=0;fat_start_lba<=0;
            data_start_lba<=0;max_cluster<=0;image_valid<=0;audio_valid<=0;
            catalog_write_enable<=0;catalog_write_address<=0;catalog_write_data<=0;
            sector_req<=0;sector_lba<=0;
            first_sector_byte<=0;partition_type<=0;mbr_partition_lba<=0;
            mbr_partition_sectors<=0;candidate_partition_lba<=0;
            boot_signature<=0;bpb_bytes_per_sector<=0;bpb_reserved_sectors<=0;
            bpb_root_entry_count<=0;bpb_fat16_sectors<=0;
            bpb_sectors_per_cluster<=0;bpb_fat_count<=0;
            bpb_total_sectors<=0;bpb_fat_sectors<=0;bpb_root_cluster<=0;
            total_sectors<=0;fat_sectors<=0;fat_span<=0;data_sector_count<=0;
            root_cluster<=0;current_root_cluster<=0;root_sector_index<=0;
            fat_count<=0;sectors_per_cluster_shift<=0;reserved_sectors<=0;
            root_cluster_count<=0;layout_offset<=0;max_cluster_pre<=0;
            lba_base<=0;root_shifted<=0;root_end_seen<=0;
            metadata_capture_q<=0;metadata_clear_q<=0;
            candidate_sectors_per_cluster_shift<=0;
            candidate_fat_span_wide<=0;candidate_layout_offset_wide<=0;
            candidate_data_sector_count_wide<=0;
            candidate_max_cluster_pre_wide<=0;candidate_max_cluster_wide<=0;
            candidate_fat_start_lba_wide<=0;
            candidate_data_start_lba_wide<=0;
            candidate_volume_end_lba_wide<=0;
            candidate_lba_base<=0;candidate_partition_bounds_bad<=0;
            candidate_fat_capacity_bad<=0;
            image_directory_fault<=0;audio_directory_fault<=0;
            entry_name_match<=0;entry_image_match<=0;entry_audio_match<=0;
            entry_candidate<=0;entry_is_audio<=0;entry_cluster_bad<=0;
            size_zero_low16<=0;entry_resource<=0;entry_cluster_high<=0;
            entry_cluster_low<=0;entry_size<=0;fat_entry_offset<=0;
            fat_byte0<=0;fat_byte1<=0;fat_byte2<=0;fat_byte3<=0;
        end else begin
            scan_done<=0;sector_req<=0;catalog_write_enable<=0;
            metadata_clear_q<=0;

            if(metadata_clear_q) begin
                first_sector_byte<=0;partition_type<=0;mbr_partition_lba<=0;
                mbr_partition_sectors<=0;
                boot_signature<=0;bpb_bytes_per_sector<=0;
                bpb_reserved_sectors<=0;bpb_root_entry_count<=0;
                bpb_fat16_sectors<=0;bpb_sectors_per_cluster<=0;
                bpb_fat_count<=0;bpb_total_sectors<=0;bpb_fat_sectors<=0;
                bpb_root_cluster<=0;
            end

            if(sector_valid && metadata_capture_q) begin
                case(sector_byte_index)
                    9'd0:first_sector_byte<=sector_byte;
                    9'd11:bpb_bytes_per_sector[7:0]<=sector_byte;
                    9'd12:bpb_bytes_per_sector[15:8]<=sector_byte;
                    9'd13:bpb_sectors_per_cluster<=sector_byte;
                    9'd14:bpb_reserved_sectors[7:0]<=sector_byte;
                    9'd15:bpb_reserved_sectors[15:8]<=sector_byte;
                    9'd16:bpb_fat_count<=sector_byte;
                    9'd17:bpb_root_entry_count[7:0]<=sector_byte;
                    9'd18:bpb_root_entry_count[15:8]<=sector_byte;
                    9'd22:bpb_fat16_sectors[7:0]<=sector_byte;
                    9'd23:bpb_fat16_sectors[15:8]<=sector_byte;
                    9'd32:bpb_total_sectors[7:0]<=sector_byte;
                    9'd33:bpb_total_sectors[15:8]<=sector_byte;
                    9'd34:bpb_total_sectors[23:16]<=sector_byte;
                    9'd35:bpb_total_sectors[31:24]<=sector_byte;
                    9'd36:bpb_fat_sectors[7:0]<=sector_byte;
                    9'd37:bpb_fat_sectors[15:8]<=sector_byte;
                    9'd38:bpb_fat_sectors[23:16]<=sector_byte;
                    9'd39:bpb_fat_sectors[31:24]<=sector_byte;
                    9'd44:bpb_root_cluster[7:0]<=sector_byte;
                    9'd45:bpb_root_cluster[15:8]<=sector_byte;
                    9'd46:bpb_root_cluster[23:16]<=sector_byte;
                    9'd47:bpb_root_cluster[31:24]<=sector_byte;
                    9'd450:partition_type<=sector_byte;
                    9'd454:mbr_partition_lba[7:0]<=sector_byte;
                    9'd455:mbr_partition_lba[15:8]<=sector_byte;
                    9'd456:mbr_partition_lba[23:16]<=sector_byte;
                    9'd457:mbr_partition_lba[31:24]<=sector_byte;
                    9'd458:mbr_partition_sectors[7:0]<=sector_byte;
                    9'd459:mbr_partition_sectors[15:8]<=sector_byte;
                    9'd460:mbr_partition_sectors[23:16]<=sector_byte;
                    9'd461:mbr_partition_sectors[31:24]<=sector_byte;
                    9'd510:boot_signature[7:0]<=sector_byte;
                    9'd511:boot_signature[15:8]<=sector_byte;
                    default:begin end
                endcase
            end

            if(sector_valid && state==ST_ROOT_WAIT && !root_end_seen) begin
                case(sector_byte_index[4:0])
                    5'd0:begin
                        entry_name_match<=sector_byte=="P";
                        entry_image_match<=0;entry_audio_match<=0;
                        entry_candidate<=0;entry_is_audio<=0;entry_resource<=0;
                        entry_cluster_high<=0;entry_cluster_low<=0;entry_size<=0;
                        entry_cluster_bad<=0;size_zero_low16<=0;
                        if(sector_byte==8'h00) root_end_seen<=1'b1;
                    end
                    5'd1:entry_name_match<=entry_name_match && sector_byte=="I";
                    5'd2:entry_name_match<=entry_name_match && sector_byte=="C";
                    5'd3:begin
                        entry_name_match<=entry_name_match && sector_byte>="1" && sector_byte<="4";
                        entry_resource<=sector_byte-"1";
                    end
                    5'd4,5'd5,5'd6,5'd7:
                        entry_name_match<=entry_name_match && sector_byte==" ";
                    5'd8:begin
                        entry_image_match<=entry_name_match && sector_byte=="B";
                        entry_audio_match<=entry_name_match && sector_byte=="W";
                    end
                    5'd9:begin
                        entry_image_match<=entry_image_match && sector_byte=="M";
                        entry_audio_match<=entry_audio_match && sector_byte=="A";
                    end
                    5'd10:begin
                        entry_image_match<=entry_image_match && sector_byte=="P";
                        entry_audio_match<=entry_audio_match && sector_byte=="V";
                    end
                    5'd11:begin
                        entry_candidate<=(entry_image_match || entry_audio_match) &&
                                        (sector_byte & 8'h18)==0 && sector_byte!=8'h0f;
                        entry_is_audio<=entry_audio_match;
                    end
                    5'd20:entry_cluster_high[7:0]<=sector_byte;
                    5'd21:entry_cluster_high[15:8]<=sector_byte;
                    5'd26:entry_cluster_low[7:0]<=sector_byte;
                    5'd27:entry_cluster_low[15:8]<=sector_byte;
                    5'd28:begin
                        entry_size[7:0]<=sector_byte;
                        entry_cluster_bad<=({entry_cluster_high,entry_cluster_low}<32'd2) ||
                                           ({entry_cluster_high,entry_cluster_low}>max_cluster);
                    end
                    5'd29:entry_size[15:8]<=sector_byte;
                    5'd30:begin
                        entry_size[23:16]<=sector_byte;
                        size_zero_low16<=entry_size[15:0]==16'd0;
                    end
                    5'd31:begin
                        // Stage the payload independently; only the validated
                        // write-enable below can commit it to catalog RAM.
                        catalog_write_data<={{entry_cluster_high,entry_cluster_low},
                                            {sector_byte,entry_size[23:0]}};
                        entry_size[31:24]<=sector_byte;
                        if(entry_candidate) accept_entry();
                    end
                    default:begin end
                endcase
            end

            if(sector_valid && state==ST_FAT_WAIT) begin
                if(sector_byte_index==fat_entry_offset) fat_byte0<=sector_byte;
                else if(sector_byte_index==fat_entry_offset+1'b1) fat_byte1<=sector_byte;
                else if(sector_byte_index==fat_entry_offset+2'd2) fat_byte2<=sector_byte;
                else if(sector_byte_index==fat_entry_offset+2'd3) fat_byte3<=sector_byte;
            end

            case(state)
                ST_IDLE:if(scan_start) begin
                    fs_error<=ERR_NONE;image_catalog_error<=ERR_NONE;
                    audio_catalog_error<=ERR_NONE;candidate_partition_lba<=0;
                    image_valid<=0;audio_valid<=0;root_end_seen<=0;
                    image_directory_fault<=0;audio_directory_fault<=0;
                    metadata_capture_q<=0;metadata_clear_q<=1;
                    candidate_sectors_per_cluster_shift<=0;
                    candidate_fat_span_wide<=0;candidate_layout_offset_wide<=0;
                    candidate_data_sector_count_wide<=0;
                    candidate_max_cluster_pre_wide<=0;
                    candidate_max_cluster_wide<=0;
                    candidate_fat_start_lba_wide<=0;
                    candidate_data_start_lba_wide<=0;
                    candidate_volume_end_lba_wide<=0;
                    candidate_lba_base<=0;candidate_partition_bounds_bad<=0;
                    candidate_fat_capacity_bad<=0;
                    state<=ST_READ0_REQ;
                end
                ST_READ0_REQ:if(!sector_busy) begin
                    metadata_capture_q<=1;
                    sector_lba<=0;sector_req<=1;state<=ST_READ0_WAIT;
                end
                ST_READ0_WAIT:if(sector_done) begin
                    metadata_capture_q<=0;
                    if(sector_error!=0) finish_with_error(ERR_SECTOR);
                    else if(boot_signature!=16'haa55) finish_with_error(ERR_BOOT_SIGNATURE);
                    else if(first_sector_byte==8'heb || first_sector_byte==8'he9) begin
                        candidate_partition_lba<=0;
                        candidate_volume_end_lba_wide<=0;
                        state<=ST_BOOT_PARSE;
                    end else if(partition_type==8'h0b || partition_type==8'h0c) begin
                        candidate_partition_lba<=mbr_partition_lba;
                        candidate_volume_end_lba_wide<=
                            {1'b0,mbr_partition_lba}+{1'b0,mbr_partition_sectors};
                        sector_lba<=mbr_partition_lba;metadata_clear_q<=1;
                        state<=ST_BOOT_REQ;
                    end else finish_with_error(ERR_UNSUPPORTED_BPB);
                end
                ST_BOOT_REQ:if(!sector_busy) begin
                    metadata_capture_q<=1;sector_req<=1;state<=ST_BOOT_WAIT;
                end
                ST_BOOT_WAIT:if(sector_done) begin
                    metadata_capture_q<=0;
                    if(sector_error!=0) finish_with_error(ERR_SECTOR);
                    else if(boot_signature!=16'haa55) finish_with_error(ERR_BOOT_SIGNATURE);
                    else state<=ST_BOOT_PARSE;
                end
                ST_BOOT_PARSE:begin
                    if(bpb_bytes_per_sector!=16'd512 || !valid_spc(bpb_sectors_per_cluster) ||
                       bpb_reserved_sectors==0 || (bpb_fat_count!=1 && bpb_fat_count!=2) ||
                       bpb_root_entry_count!=0 || bpb_fat16_sectors!=0 ||
                       bpb_total_sectors==0 || bpb_fat_sectors==0 ||
                       bpb_root_cluster<2 || bpb_root_cluster>32'h0fff_ffef)
                        finish_with_error(ERR_UNSUPPORTED_BPB);
                    else begin
                        candidate_sectors_per_cluster_shift<=
                            spc_shift(bpb_sectors_per_cluster);
                        candidate_fat_span_wide<=bpb_fat_count==2 ?
                            ({1'b0,bpb_fat_sectors}<<1) :
                            {1'b0,bpb_fat_sectors};
                        state<=ST_LAYOUT;
                    end
                end
                ST_LAYOUT:begin
                    candidate_layout_offset_wide<=
                        {18'd0,bpb_reserved_sectors}+{1'b0,candidate_fat_span_wide};
                    state<=ST_LAYOUT2;
                end
                ST_LAYOUT2:begin
                    if(candidate_layout_offset_wide >= {2'b0,bpb_total_sectors})
                        finish_with_error(ERR_UNSUPPORTED_BPB);
                    else begin
                        candidate_data_sector_count_wide<=
                            {1'b0,bpb_total_sectors}-candidate_layout_offset_wide;
                        candidate_fat_start_lba_wide<=
                            {1'b0,candidate_partition_lba}+
                            {17'd0,bpb_reserved_sectors};
                        candidate_data_start_lba_wide<=
                            {1'b0,candidate_partition_lba}+
                            {1'b0,candidate_layout_offset_wide[31:0]};
                        candidate_partition_bounds_bad<=
                            candidate_partition_lba!=0 &&
                            (candidate_volume_end_lba_wide[32] ||
                             candidate_volume_end_lba_wide<=
                                {1'b0,candidate_partition_lba} ||
                             ({1'b0,candidate_partition_lba}+
                              {1'b0,bpb_total_sectors})>
                                candidate_volume_end_lba_wide);
                        candidate_volume_end_lba_wide<=
                            {1'b0,candidate_partition_lba}+
                            {1'b0,bpb_total_sectors};
                        state<=ST_LAYOUT3;
                    end
                end
                ST_LAYOUT3:begin
                    if(candidate_partition_bounds_bad ||
                       candidate_volume_end_lba_wide>33'h100000000 ||
                       candidate_fat_start_lba_wide[32] ||
                       candidate_data_start_lba_wide[32])
                        finish_with_error(ERR_UNSUPPORTED_BPB);
                    else state<=ST_LAYOUT4;
                end
                ST_LAYOUT4:begin
                    candidate_max_cluster_pre_wide<=
                        candidate_data_sector_count_wide>>
                        candidate_sectors_per_cluster_shift;
                    candidate_lba_base<=candidate_data_start_lba_wide[31:0]-
                        (32'd2<<candidate_sectors_per_cluster_shift);
                    state<=ST_LAYOUT5;
                end
                ST_LAYOUT5:begin
                    candidate_max_cluster_wide<=
                        candidate_max_cluster_pre_wide+33'd1;
                    candidate_fat_capacity_bad<=
                        candidate_max_cluster_pre_wide>=33'd268435439 ||
                        (((candidate_max_cluster_pre_wide+33'd1)>>7)>=
                         {1'b0,bpb_fat_sectors});
                    state<=ST_BOOT_COMMIT;
                end
                ST_BOOT_COMMIT:begin
                    if(candidate_fat_capacity_bad)
                        finish_with_error(ERR_UNSUPPORTED_BPB);
                    else if({1'b0,bpb_root_cluster}>candidate_max_cluster_wide)
                        finish_with_error(ERR_ROOT_CHAIN);
                    else begin
                        partition_lba<=candidate_partition_lba;
                        sectors_per_cluster<=bpb_sectors_per_cluster;
                        fat_start_lba<=candidate_fat_start_lba_wide[31:0];
                        data_start_lba<=candidate_data_start_lba_wide[31:0];
                        max_cluster<=candidate_max_cluster_wide[31:0];
                        sectors_per_cluster_shift<=
                            candidate_sectors_per_cluster_shift;
                        reserved_sectors<=bpb_reserved_sectors;
                        fat_count<=bpb_fat_count;
                        total_sectors<=bpb_total_sectors;
                        fat_sectors<=bpb_fat_sectors;
                        root_cluster<=bpb_root_cluster;
                        fat_span<=candidate_fat_span_wide[31:0];
                        layout_offset<=candidate_layout_offset_wide[31:0];
                        data_sector_count<=candidate_data_sector_count_wide[31:0];
                        max_cluster_pre<=candidate_max_cluster_pre_wide[31:0];
                        lba_base<=candidate_lba_base;
                        state<=ST_ROOT_INIT;
                    end
                end
                ST_ROOT_INIT:begin
                    root_sector_index<=0;
                    if(root_cluster>max_cluster)
                        finish_with_error(ERR_ROOT_CHAIN);
                    else begin
                        current_root_cluster<=root_cluster;root_cluster_count<=1;
                        root_end_seen<=0;state<=ST_ROOT_LBA1;
                    end
                end
                ST_ROOT_LBA1:begin
                    root_shifted<=current_root_cluster<<sectors_per_cluster_shift;
                    state<=ST_ROOT_LBA2;
                end
                ST_ROOT_LBA2:begin sector_lba<=root_shifted+lba_base;state<=ST_ROOT_REQ;end
                ST_ROOT_REQ:if(!sector_busy) begin sector_req<=1;state<=ST_ROOT_WAIT;end
                ST_ROOT_WAIT:if(sector_done) begin
                    if(sector_error!=0) finish_with_error(ERR_SECTOR);
                    else if(catalogs_complete) state<=ST_FINISH;
                    else if(root_end_seen) state<=ST_FINISH;
                    else if(root_sector_index+1'b1<sectors_per_cluster) begin
                        root_sector_index<=root_sector_index+1'b1;
                        sector_lba<=sector_lba+1'b1;state<=ST_ROOT_REQ;
                    end else begin
                        root_sector_index<=0;
                        fat_entry_offset<={current_root_cluster[6:0],2'b00};
                        sector_lba<=fat_start_lba+(current_root_cluster>>7);
                        state<=ST_FAT_REQ;
                    end
                end
                ST_FAT_REQ:if(!sector_busy) begin sector_req<=1;state<=ST_FAT_WAIT;end
                ST_FAT_WAIT:if(sector_done) begin
                    if(sector_error!=0) finish_with_error(ERR_SECTOR);
                    else state<=ST_FAT_PARSE;
                end
                ST_FAT_PARSE:begin
                    if(next_root_cluster[27:4]==24'hffffff &&
                       next_root_cluster[3]) state<=ST_FINISH;
                    else if(next_root_cluster[27:4]==24'hffffff)
                        finish_with_error(ERR_ROOT_CHAIN);
                    else if(next_root_cluster<2 || next_root_cluster>max_cluster)
                        finish_with_error(ERR_ROOT_CHAIN);
                    else if(next_root_cluster==current_root_cluster)
                        finish_with_error(ERR_ROOT_LOOP);
                    else if(root_cluster_count>=MAX_ROOT_CLUSTERS)
                        finish_with_error(ERR_ROOT_VISITED);
                    else begin
                        current_root_cluster<={4'd0,next_root_cluster};
                        root_cluster_count<=root_cluster_count+1'b1;
                        state<=ST_ROOT_LBA1;
                    end
                end
                ST_FINISH:begin
                    if(fs_error==ERR_NONE) begin
                        if(image_directory_fault) image_catalog_error<=ERR_DIRECTORY_ENTRY;
                        else if(image_valid!=4'hf) image_catalog_error<=ERR_RESOURCE_MISSING;
                        else image_catalog_error<=ERR_NONE;
                        if(audio_directory_fault) audio_catalog_error<=ERR_DIRECTORY_ENTRY;
                        else if(audio_valid!=4'hf) audio_catalog_error<=ERR_RESOURCE_MISSING;
                        else audio_catalog_error<=ERR_NONE;
                    end
                    scan_done<=1;state<=ST_IDLE;
                end
                default:state<=ST_IDLE;
            endcase
        end
    end
endmodule
