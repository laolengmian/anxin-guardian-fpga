// Generated shared Product/Diagnostic sparse text descriptors.
module m9_ui_text_rom (
    input wire clk,input wire diagnostic,input wire [3:0] line_index,
    input wire [6:0] column_index,output reg [12:0] descriptor
);
    reg [12:0] text_mem [0:4095] /* fehdl force_ram=1, ram_style="bram" */;
    integer index;
    initial begin
        for(index=0;index<4096;index=index+1) text_mem[index]=0;
        text_mem[130]=13'h242; text_mem[131]=13'h342; text_mem[132]=13'h26b; text_mem[133]=13'h36b; text_mem[134]=13'h241; text_mem[135]=13'h341; text_mem[136]=13'h24e; text_mem[137]=13'h34e;
        text_mem[142]=13'h4e; text_mem[143]=13'h14e; text_mem[144]=13'h61; text_mem[145]=13'h161; text_mem[146]=13'h2a; text_mem[147]=13'h12a; text_mem[148]=13'h78; text_mem[149]=13'h178;
        text_mem[151]=13'h2b8; text_mem[160]=13'h1403; text_mem[161]=13'h140b; text_mem[162]=13'h1447; text_mem[163]=13'h1547; text_mem[164]=13'h0; text_mem[165]=13'h0; text_mem[166]=13'h0;
        text_mem[167]=13'h0; text_mem[168]=13'h0; text_mem[169]=13'h0; text_mem[170]=13'h0; text_mem[171]=13'h0; text_mem[184]=13'h4c0; text_mem[185]=13'h5c0; text_mem[186]=13'h4c1;
        text_mem[187]=13'h5c1; text_mem[188]=13'h4c2; text_mem[189]=13'h5c2; text_mem[190]=13'h4c3; text_mem[191]=13'h5c3; text_mem[192]=13'h4c4; text_mem[193]=13'h5c4; text_mem[194]=13'h4c5;
        text_mem[195]=13'h5c5; text_mem[386]=13'h22c; text_mem[387]=13'h32c; text_mem[388]=13'h253; text_mem[389]=13'h353; text_mem[390]=13'h24e; text_mem[391]=13'h34e; text_mem[392]=13'h261;
        text_mem[393]=13'h361; text_mem[394]=13'h26d; text_mem[395]=13'h36d; text_mem[396]=13'h235; text_mem[397]=13'h335; text_mem[642]=13'h3; text_mem[643]=13'hb; text_mem[644]=13'h27;
        text_mem[645]=13'h3; text_mem[646]=13'h3; text_mem[647]=13'h54; text_mem[648]=13'h154; text_mem[649]=13'h79; text_mem[650]=13'h179; text_mem[770]=13'h3; text_mem[771]=13'hc;
        text_mem[772]=13'h27; text_mem[773]=13'h6; text_mem[774]=13'h3; text_mem[775]=13'h58; text_mem[776]=13'h158; text_mem[777]=13'h57; text_mem[778]=13'h157; text_mem[1026]=13'h4;
        text_mem[1027]=13'h7; text_mem[1028]=13'h27; text_mem[1029]=13'h3; text_mem[1030]=13'h3; text_mem[1031]=13'h49; text_mem[1032]=13'h149; text_mem[1033]=13'h3e; text_mem[1034]=13'h13e;
        text_mem[1035]=13'h6e; text_mem[1036]=13'h16e; text_mem[1037]=13'h69; text_mem[1038]=13'h169; text_mem[1154]=13'h4; text_mem[1155]=13'h9; text_mem[1156]=13'h27; text_mem[1157]=13'h3;
        text_mem[1158]=13'h3; text_mem[1159]=13'h2f; text_mem[1160]=13'h12f; text_mem[1161]=13'h49; text_mem[1162]=13'h149; text_mem[1163]=13'h43; text_mem[1164]=13'h143; text_mem[1165]=13'h51;
        text_mem[1166]=13'h151; text_mem[1601]=13'h32; text_mem[1602]=13'h132; text_mem[1603]=13'h44; text_mem[1604]=13'h144; text_mem[1605]=13'h2b; text_mem[1606]=13'h12b; text_mem[1607]=13'h48;
        text_mem[1608]=13'h148; text_mem[1610]=13'h2b9; text_mem[2178]=13'h212; text_mem[2179]=13'h21c; text_mem[2180]=13'h213; text_mem[2181]=13'h20d; text_mem[2182]=13'h267; text_mem[2183]=13'h367;
        text_mem[2184]=13'h26a; text_mem[2185]=13'h36a; text_mem[2186]=13'h25f; text_mem[2187]=13'h35f; text_mem[2188]=13'h24c; text_mem[2189]=13'h34c; text_mem[2244]=13'h481; text_mem[2245]=13'h482;
        text_mem[2246]=13'h483; text_mem[2247]=13'h484; text_mem[2248]=13'h485; text_mem[2249]=13'h486; text_mem[2250]=13'h487; text_mem[2251]=13'h488; text_mem[2252]=13'h489; text_mem[2306]=13'h245;
        text_mem[2307]=13'h345; text_mem[2308]=13'h272; text_mem[2309]=13'h372; text_mem[2310]=13'h240; text_mem[2311]=13'h340; text_mem[2312]=13'h250; text_mem[2313]=13'h350; text_mem[2314]=13'h276;
        text_mem[2315]=13'h376; text_mem[2371]=13'he8a; text_mem[2372]=13'he8b; text_mem[2373]=13'he8c; text_mem[2374]=13'he8d; text_mem[2375]=13'he8e; text_mem[2376]=13'he8f; text_mem[2562]=13'h242;
        text_mem[2563]=13'h342; text_mem[2564]=13'h232; text_mem[2565]=13'h332; text_mem[2566]=13'h202; text_mem[2567]=13'h24d; text_mem[2568]=13'h34d; text_mem[2569]=13'h23e; text_mem[2570]=13'h33e;
        text_mem[2571]=13'h25f; text_mem[2572]=13'h35f; text_mem[2573]=13'h24c; text_mem[2574]=13'h34c; text_mem[2588]=13'h23f; text_mem[2589]=13'h33f; text_mem[2590]=13'h22e; text_mem[2591]=13'h32e;
        text_mem[2592]=13'h273; text_mem[2593]=13'h373; text_mem[2594]=13'h270; text_mem[2595]=13'h370; text_mem[2596]=13'h274; text_mem[2597]=13'h374; text_mem[2598]=13'h25b; text_mem[2599]=13'h35b;
        text_mem[2614]=13'h23f; text_mem[2615]=13'h33f; text_mem[2616]=13'h22e; text_mem[2617]=13'h32e; text_mem[2618]=13'h273; text_mem[2619]=13'h373; text_mem[2620]=13'h270; text_mem[2621]=13'h370;
        text_mem[2622]=13'h22d; text_mem[2623]=13'h32d; text_mem[2624]=13'h265; text_mem[2625]=13'h365; text_mem[2818]=13'h90; text_mem[2819]=13'h91; text_mem[2820]=13'h92; text_mem[2821]=13'h93;
        text_mem[2822]=13'h94; text_mem[2823]=13'h95; text_mem[2824]=13'h96; text_mem[2844]=13'h1097; text_mem[2845]=13'h1098; text_mem[2846]=13'h1099; text_mem[2847]=13'h109a; text_mem[2848]=13'h109b;
        text_mem[2849]=13'h109c; text_mem[2870]=13'h109d; text_mem[2871]=13'h109e; text_mem[2872]=13'h109f; text_mem[2873]=13'h10a0; text_mem[2874]=13'h10a1; text_mem[2875]=13'h10a2;
    end
    always @(posedge clk) descriptor<=text_mem[{diagnostic,line_index,column_index}];
endmodule
module m9_ui_line_index(input wire [4:0] physical_row,output reg [3:0] line_index);
    always @(*) begin
        line_index=0;
        case(physical_row)
            5'd1:line_index=4'd1;
            5'd4:line_index=4'd2;
            5'd6:line_index=4'd3;
            5'd7:line_index=4'd4;
            5'd8:line_index=4'd5;
            5'd9:line_index=4'd6;
            5'd10:line_index=4'd7;
            5'd11:line_index=4'd8;
            5'd12:line_index=4'd9;
            5'd13:line_index=4'd10;
            5'd14:line_index=4'd11;
            5'd15:line_index=4'd12;
            5'd16:line_index=4'd13;
        endcase
    end
endmodule
