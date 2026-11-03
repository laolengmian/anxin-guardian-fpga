// Highest-priority M9 local status layer. SAFE/RECOVER pixels depend only on
// coordinates and a frame-latched Health bundle, never on media RGB. DEGRADED
// is confined to the left pillarbox so the 960-pixel media area is untouched.
module m9_safe_renderer (
    input wire clk,input wire rst,
    input wire in_valid,input wire in_user,input wire in_last,
    input wire [14:0] in_x,input wire [14:0] in_y,input wire [23:0] in_rgb,
    input wire [1:0] failsafe_state_pending,input wire [1:0] health_status_pending,
    input wire [7:0] error_code_pending,
    output reg out_valid,output reg out_user,output reg out_last,
    output reg [14:0] out_x,output reg [14:0] out_y,output reg [23:0] out_rgb
);
    localparam [1:0] DEGRADED=2'd1,SAFE=2'd2,RECOVER=2'd3;
    localparam [23:0] SAFE_BG_A=24'h07111f,SAFE_BG_B=24'h0a1829;
    localparam [23:0] SAFE_PANEL=24'h23131c,SAFE_RAIL=24'hff4057;
    localparam [23:0] SAFE_TEXT=24'hfff4e8,SAFE_ACCENT=24'hffcc66;
    localparam [23:0] RECOVER_RAIL=24'hf2b84b,RECOVER_TEXT=24'hfff1c2;
    localparam [23:0] DEGRADED_BG=24'h4a3500,DEGRADED_BORDER=24'hffd447;
    localparam [23:0] DEGRADED_TEXT=24'hfff4c2;

    reg [1:0] failsafe_state_q,health_status_q;
    reg [7:0] error_code_q;
    wire first=in_valid && in_user;
    wire [1:0] failsafe_state=first ? failsafe_state_pending : failsafe_state_q;
    wire [1:0] health_status=first ? health_status_pending : health_status_q;
    wire [7:0] error_code=first ? error_code_pending : error_code_q;
    wire safe_active=failsafe_state==SAFE || failsafe_state==RECOVER;
    wire recovering=failsafe_state==RECOVER;
    wire degraded_active=!safe_active && health_status==DEGRADED;
    wire in_canvas,safe_border,safe_center_panel,degraded_panel,degraded_border;
    wire safe_title_text,safe_state_text,safe_error_text,degraded_text;
    m9_safe_regions u_regions(
        .clk(clk),.in_x(in_x),.in_y(in_y),.in_canvas(in_canvas),.safe_border(safe_border),
        .safe_center_panel(safe_center_panel),.degraded_panel(degraded_panel),
        .degraded_border(degraded_border),.safe_title_text(safe_title_text),
        .safe_state_text(safe_state_text),.safe_error_text(safe_error_text),
        .degraded_text(degraded_text));
    reg region_valid_q,region_user_q,region_last_q;
    reg [14:0] region_x_q,region_y_q;
    reg [23:0] region_rgb_q;

    reg [4:0] glyph_mem [0:1023] /* fehdl force_ram=1, ram_style="bram" */;
    integer init_index;
    initial begin
        for(init_index=0;init_index<1024;init_index=init_index+1)
            glyph_mem[init_index]=5'd0;
        glyph_mem[10'd144]=5'b11111;glyph_mem[10'd145]=5'b10000;glyph_mem[10'd146]=5'b10000;glyph_mem[10'd147]=5'b01110;glyph_mem[10'd148]=5'b00001;glyph_mem[10'd149]=5'b00001;glyph_mem[10'd150]=5'b11110;
        glyph_mem[10'd152]=5'b10001;glyph_mem[10'd153]=5'b10001;glyph_mem[10'd154]=5'b01010;glyph_mem[10'd155]=5'b00100;glyph_mem[10'd156]=5'b00100;glyph_mem[10'd157]=5'b00100;glyph_mem[10'd158]=5'b00100;
        glyph_mem[10'd160]=5'b11111;glyph_mem[10'd161]=5'b10000;glyph_mem[10'd162]=5'b10000;glyph_mem[10'd163]=5'b01110;glyph_mem[10'd164]=5'b00001;glyph_mem[10'd165]=5'b00001;glyph_mem[10'd166]=5'b11110;
        glyph_mem[10'd168]=5'b11111;glyph_mem[10'd169]=5'b00100;glyph_mem[10'd170]=5'b00100;glyph_mem[10'd171]=5'b00100;glyph_mem[10'd172]=5'b00100;glyph_mem[10'd173]=5'b00100;glyph_mem[10'd174]=5'b00100;
        glyph_mem[10'd176]=5'b11111;glyph_mem[10'd177]=5'b10000;glyph_mem[10'd178]=5'b10000;glyph_mem[10'd179]=5'b11110;glyph_mem[10'd180]=5'b10000;glyph_mem[10'd181]=5'b10000;glyph_mem[10'd182]=5'b11111;
        glyph_mem[10'd184]=5'b10001;glyph_mem[10'd185]=5'b11011;glyph_mem[10'd186]=5'b10101;glyph_mem[10'd187]=5'b10101;glyph_mem[10'd188]=5'b10001;glyph_mem[10'd189]=5'b10001;glyph_mem[10'd190]=5'b10001;
        glyph_mem[10'd192]=5'b00000;glyph_mem[10'd193]=5'b00000;glyph_mem[10'd194]=5'b00000;glyph_mem[10'd195]=5'b00000;glyph_mem[10'd196]=5'b00000;glyph_mem[10'd197]=5'b00000;glyph_mem[10'd198]=5'b00000;
        glyph_mem[10'd200]=5'b11111;glyph_mem[10'd201]=5'b10000;glyph_mem[10'd202]=5'b10000;glyph_mem[10'd203]=5'b01110;glyph_mem[10'd204]=5'b00001;glyph_mem[10'd205]=5'b00001;glyph_mem[10'd206]=5'b11110;
        glyph_mem[10'd208]=5'b01110;glyph_mem[10'd209]=5'b10001;glyph_mem[10'd210]=5'b10001;glyph_mem[10'd211]=5'b11111;glyph_mem[10'd212]=5'b10001;glyph_mem[10'd213]=5'b10001;glyph_mem[10'd214]=5'b10001;
        glyph_mem[10'd216]=5'b11111;glyph_mem[10'd217]=5'b10000;glyph_mem[10'd218]=5'b10000;glyph_mem[10'd219]=5'b11110;glyph_mem[10'd220]=5'b10000;glyph_mem[10'd221]=5'b10000;glyph_mem[10'd222]=5'b10000;
        glyph_mem[10'd224]=5'b11111;glyph_mem[10'd225]=5'b10000;glyph_mem[10'd226]=5'b10000;glyph_mem[10'd227]=5'b11110;glyph_mem[10'd228]=5'b10000;glyph_mem[10'd229]=5'b10000;glyph_mem[10'd230]=5'b11111;
        glyph_mem[10'd264]=5'b10001;glyph_mem[10'd265]=5'b11011;glyph_mem[10'd266]=5'b10101;glyph_mem[10'd267]=5'b10101;glyph_mem[10'd268]=5'b10001;glyph_mem[10'd269]=5'b10001;glyph_mem[10'd270]=5'b10001;
        glyph_mem[10'd272]=5'b11111;glyph_mem[10'd273]=5'b10000;glyph_mem[10'd274]=5'b10000;glyph_mem[10'd275]=5'b11110;glyph_mem[10'd276]=5'b10000;glyph_mem[10'd277]=5'b10000;glyph_mem[10'd278]=5'b11111;
        glyph_mem[10'd280]=5'b11110;glyph_mem[10'd281]=5'b10001;glyph_mem[10'd282]=5'b10001;glyph_mem[10'd283]=5'b10001;glyph_mem[10'd284]=5'b10001;glyph_mem[10'd285]=5'b10001;glyph_mem[10'd286]=5'b11110;
        glyph_mem[10'd288]=5'b11111;glyph_mem[10'd289]=5'b00100;glyph_mem[10'd290]=5'b00100;glyph_mem[10'd291]=5'b00100;glyph_mem[10'd292]=5'b00100;glyph_mem[10'd293]=5'b00100;glyph_mem[10'd294]=5'b11111;
        glyph_mem[10'd296]=5'b01110;glyph_mem[10'd297]=5'b10001;glyph_mem[10'd298]=5'b10001;glyph_mem[10'd299]=5'b11111;glyph_mem[10'd300]=5'b10001;glyph_mem[10'd301]=5'b10001;glyph_mem[10'd302]=5'b10001;
        glyph_mem[10'd304]=5'b00000;glyph_mem[10'd305]=5'b00000;glyph_mem[10'd306]=5'b00000;glyph_mem[10'd307]=5'b00000;glyph_mem[10'd308]=5'b00000;glyph_mem[10'd309]=5'b00000;glyph_mem[10'd310]=5'b00000;
        glyph_mem[10'd312]=5'b01110;glyph_mem[10'd313]=5'b10001;glyph_mem[10'd314]=5'b10001;glyph_mem[10'd315]=5'b10001;glyph_mem[10'd316]=5'b10001;glyph_mem[10'd317]=5'b10001;glyph_mem[10'd318]=5'b01110;
        glyph_mem[10'd320]=5'b11111;glyph_mem[10'd321]=5'b10000;glyph_mem[10'd322]=5'b10000;glyph_mem[10'd323]=5'b11110;glyph_mem[10'd324]=5'b10000;glyph_mem[10'd325]=5'b10000;glyph_mem[10'd326]=5'b10000;
        glyph_mem[10'd328]=5'b11111;glyph_mem[10'd329]=5'b10000;glyph_mem[10'd330]=5'b10000;glyph_mem[10'd331]=5'b11110;glyph_mem[10'd332]=5'b10000;glyph_mem[10'd333]=5'b10000;glyph_mem[10'd334]=5'b10000;
        glyph_mem[10'd336]=5'b10000;glyph_mem[10'd337]=5'b10000;glyph_mem[10'd338]=5'b10000;glyph_mem[10'd339]=5'b10000;glyph_mem[10'd340]=5'b10000;glyph_mem[10'd341]=5'b10000;glyph_mem[10'd342]=5'b11111;
        glyph_mem[10'd344]=5'b11111;glyph_mem[10'd345]=5'b00100;glyph_mem[10'd346]=5'b00100;glyph_mem[10'd347]=5'b00100;glyph_mem[10'd348]=5'b00100;glyph_mem[10'd349]=5'b00100;glyph_mem[10'd350]=5'b11111;
        glyph_mem[10'd352]=5'b10001;glyph_mem[10'd353]=5'b11001;glyph_mem[10'd354]=5'b10101;glyph_mem[10'd355]=5'b10011;glyph_mem[10'd356]=5'b10001;glyph_mem[10'd357]=5'b10001;glyph_mem[10'd358]=5'b10001;
        glyph_mem[10'd360]=5'b11111;glyph_mem[10'd361]=5'b10000;glyph_mem[10'd362]=5'b10000;glyph_mem[10'd363]=5'b11110;glyph_mem[10'd364]=5'b10000;glyph_mem[10'd365]=5'b10000;glyph_mem[10'd366]=5'b11111;
        glyph_mem[10'd392]=5'b11110;glyph_mem[10'd393]=5'b10001;glyph_mem[10'd394]=5'b10001;glyph_mem[10'd395]=5'b11110;glyph_mem[10'd396]=5'b10100;glyph_mem[10'd397]=5'b10010;glyph_mem[10'd398]=5'b10001;
        glyph_mem[10'd400]=5'b11111;glyph_mem[10'd401]=5'b10000;glyph_mem[10'd402]=5'b10000;glyph_mem[10'd403]=5'b11110;glyph_mem[10'd404]=5'b10000;glyph_mem[10'd405]=5'b10000;glyph_mem[10'd406]=5'b11111;
        glyph_mem[10'd408]=5'b01111;glyph_mem[10'd409]=5'b10000;glyph_mem[10'd410]=5'b10000;glyph_mem[10'd411]=5'b10000;glyph_mem[10'd412]=5'b10000;glyph_mem[10'd413]=5'b10000;glyph_mem[10'd414]=5'b01111;
        glyph_mem[10'd416]=5'b01110;glyph_mem[10'd417]=5'b10001;glyph_mem[10'd418]=5'b10001;glyph_mem[10'd419]=5'b10001;glyph_mem[10'd420]=5'b10001;glyph_mem[10'd421]=5'b10001;glyph_mem[10'd422]=5'b01110;
        glyph_mem[10'd424]=5'b10001;glyph_mem[10'd425]=5'b10001;glyph_mem[10'd426]=5'b10001;glyph_mem[10'd427]=5'b10001;glyph_mem[10'd428]=5'b10001;glyph_mem[10'd429]=5'b01010;glyph_mem[10'd430]=5'b00100;
        glyph_mem[10'd432]=5'b11111;glyph_mem[10'd433]=5'b10000;glyph_mem[10'd434]=5'b10000;glyph_mem[10'd435]=5'b11110;glyph_mem[10'd436]=5'b10000;glyph_mem[10'd437]=5'b10000;glyph_mem[10'd438]=5'b11111;
        glyph_mem[10'd440]=5'b11110;glyph_mem[10'd441]=5'b10001;glyph_mem[10'd442]=5'b10001;glyph_mem[10'd443]=5'b11110;glyph_mem[10'd444]=5'b10100;glyph_mem[10'd445]=5'b10010;glyph_mem[10'd446]=5'b10001;
        glyph_mem[10'd448]=5'b11111;glyph_mem[10'd449]=5'b00100;glyph_mem[10'd450]=5'b00100;glyph_mem[10'd451]=5'b00100;glyph_mem[10'd452]=5'b00100;glyph_mem[10'd453]=5'b00100;glyph_mem[10'd454]=5'b11111;
        glyph_mem[10'd456]=5'b10001;glyph_mem[10'd457]=5'b11001;glyph_mem[10'd458]=5'b10101;glyph_mem[10'd459]=5'b10011;glyph_mem[10'd460]=5'b10001;glyph_mem[10'd461]=5'b10001;glyph_mem[10'd462]=5'b10001;
        glyph_mem[10'd464]=5'b01111;glyph_mem[10'd465]=5'b10000;glyph_mem[10'd466]=5'b10000;glyph_mem[10'd467]=5'b10111;glyph_mem[10'd468]=5'b10001;glyph_mem[10'd469]=5'b10001;glyph_mem[10'd470]=5'b01111;
        glyph_mem[10'd536]=5'b11111;glyph_mem[10'd537]=5'b10000;glyph_mem[10'd538]=5'b10000;glyph_mem[10'd539]=5'b11110;glyph_mem[10'd540]=5'b10000;glyph_mem[10'd541]=5'b10000;glyph_mem[10'd542]=5'b11111;
        glyph_mem[10'd544]=5'b11110;glyph_mem[10'd545]=5'b10001;glyph_mem[10'd546]=5'b10001;glyph_mem[10'd547]=5'b11110;glyph_mem[10'd548]=5'b10100;glyph_mem[10'd549]=5'b10010;glyph_mem[10'd550]=5'b10001;
        glyph_mem[10'd552]=5'b11110;glyph_mem[10'd553]=5'b10001;glyph_mem[10'd554]=5'b10001;glyph_mem[10'd555]=5'b11110;glyph_mem[10'd556]=5'b10100;glyph_mem[10'd557]=5'b10010;glyph_mem[10'd558]=5'b10001;
        glyph_mem[10'd560]=5'b01110;glyph_mem[10'd561]=5'b10001;glyph_mem[10'd562]=5'b10001;glyph_mem[10'd563]=5'b10001;glyph_mem[10'd564]=5'b10001;glyph_mem[10'd565]=5'b10001;glyph_mem[10'd566]=5'b01110;
        glyph_mem[10'd568]=5'b11110;glyph_mem[10'd569]=5'b10001;glyph_mem[10'd570]=5'b10001;glyph_mem[10'd571]=5'b11110;glyph_mem[10'd572]=5'b10100;glyph_mem[10'd573]=5'b10010;glyph_mem[10'd574]=5'b10001;
        glyph_mem[10'd576]=5'b00000;glyph_mem[10'd577]=5'b00000;glyph_mem[10'd578]=5'b00000;glyph_mem[10'd579]=5'b00000;glyph_mem[10'd580]=5'b00000;glyph_mem[10'd581]=5'b00000;glyph_mem[10'd582]=5'b00000;
        glyph_mem[10'd584]=5'b01110;glyph_mem[10'd585]=5'b10001;glyph_mem[10'd586]=5'b10011;glyph_mem[10'd587]=5'b10101;glyph_mem[10'd588]=5'b11001;glyph_mem[10'd589]=5'b10001;glyph_mem[10'd590]=5'b01110;
        glyph_mem[10'd592]=5'b10001;glyph_mem[10'd593]=5'b10001;glyph_mem[10'd594]=5'b01010;glyph_mem[10'd595]=5'b00100;glyph_mem[10'd596]=5'b01010;glyph_mem[10'd597]=5'b10001;glyph_mem[10'd598]=5'b10001;
        glyph_mem[10'd664]=5'b10001;glyph_mem[10'd665]=5'b10001;glyph_mem[10'd666]=5'b10001;glyph_mem[10'd667]=5'b11111;glyph_mem[10'd668]=5'b10001;glyph_mem[10'd669]=5'b10001;glyph_mem[10'd670]=5'b10001;
        glyph_mem[10'd672]=5'b11111;glyph_mem[10'd673]=5'b10000;glyph_mem[10'd674]=5'b10000;glyph_mem[10'd675]=5'b11110;glyph_mem[10'd676]=5'b10000;glyph_mem[10'd677]=5'b10000;glyph_mem[10'd678]=5'b11111;
        glyph_mem[10'd680]=5'b01110;glyph_mem[10'd681]=5'b10001;glyph_mem[10'd682]=5'b10001;glyph_mem[10'd683]=5'b11111;glyph_mem[10'd684]=5'b10001;glyph_mem[10'd685]=5'b10001;glyph_mem[10'd686]=5'b10001;
        glyph_mem[10'd688]=5'b10000;glyph_mem[10'd689]=5'b10000;glyph_mem[10'd690]=5'b10000;glyph_mem[10'd691]=5'b10000;glyph_mem[10'd692]=5'b10000;glyph_mem[10'd693]=5'b10000;glyph_mem[10'd694]=5'b11111;
        glyph_mem[10'd696]=5'b11111;glyph_mem[10'd697]=5'b00100;glyph_mem[10'd698]=5'b00100;glyph_mem[10'd699]=5'b00100;glyph_mem[10'd700]=5'b00100;glyph_mem[10'd701]=5'b00100;glyph_mem[10'd702]=5'b00100;
        glyph_mem[10'd704]=5'b10001;glyph_mem[10'd705]=5'b10001;glyph_mem[10'd706]=5'b10001;glyph_mem[10'd707]=5'b11111;glyph_mem[10'd708]=5'b10001;glyph_mem[10'd709]=5'b10001;glyph_mem[10'd710]=5'b10001;
        glyph_mem[10'd792]=5'b11110;glyph_mem[10'd793]=5'b10001;glyph_mem[10'd794]=5'b10001;glyph_mem[10'd795]=5'b10001;glyph_mem[10'd796]=5'b10001;glyph_mem[10'd797]=5'b10001;glyph_mem[10'd798]=5'b11110;
        glyph_mem[10'd800]=5'b11111;glyph_mem[10'd801]=5'b10000;glyph_mem[10'd802]=5'b10000;glyph_mem[10'd803]=5'b11110;glyph_mem[10'd804]=5'b10000;glyph_mem[10'd805]=5'b10000;glyph_mem[10'd806]=5'b11111;
        glyph_mem[10'd808]=5'b01111;glyph_mem[10'd809]=5'b10000;glyph_mem[10'd810]=5'b10000;glyph_mem[10'd811]=5'b10111;glyph_mem[10'd812]=5'b10001;glyph_mem[10'd813]=5'b10001;glyph_mem[10'd814]=5'b01111;
        glyph_mem[10'd816]=5'b11110;glyph_mem[10'd817]=5'b10001;glyph_mem[10'd818]=5'b10001;glyph_mem[10'd819]=5'b11110;glyph_mem[10'd820]=5'b10100;glyph_mem[10'd821]=5'b10010;glyph_mem[10'd822]=5'b10001;
        glyph_mem[10'd824]=5'b01110;glyph_mem[10'd825]=5'b10001;glyph_mem[10'd826]=5'b10001;glyph_mem[10'd827]=5'b11111;glyph_mem[10'd828]=5'b10001;glyph_mem[10'd829]=5'b10001;glyph_mem[10'd830]=5'b10001;
        glyph_mem[10'd832]=5'b11110;glyph_mem[10'd833]=5'b10001;glyph_mem[10'd834]=5'b10001;glyph_mem[10'd835]=5'b10001;glyph_mem[10'd836]=5'b10001;glyph_mem[10'd837]=5'b10001;glyph_mem[10'd838]=5'b11110;
        glyph_mem[10'd840]=5'b11111;glyph_mem[10'd841]=5'b10000;glyph_mem[10'd842]=5'b10000;glyph_mem[10'd843]=5'b11110;glyph_mem[10'd844]=5'b10000;glyph_mem[10'd845]=5'b10000;glyph_mem[10'd846]=5'b11111;
        glyph_mem[10'd848]=5'b11110;glyph_mem[10'd849]=5'b10001;glyph_mem[10'd850]=5'b10001;glyph_mem[10'd851]=5'b10001;glyph_mem[10'd852]=5'b10001;glyph_mem[10'd853]=5'b10001;glyph_mem[10'd854]=5'b11110;
        glyph_mem[10'd896]=5'b01110;glyph_mem[10'd897]=5'b10001;glyph_mem[10'd898]=5'b10011;glyph_mem[10'd899]=5'b10101;glyph_mem[10'd900]=5'b11001;glyph_mem[10'd901]=5'b10001;glyph_mem[10'd902]=5'b01110;
        glyph_mem[10'd904]=5'b00100;glyph_mem[10'd905]=5'b01100;glyph_mem[10'd906]=5'b00100;glyph_mem[10'd907]=5'b00100;glyph_mem[10'd908]=5'b00100;glyph_mem[10'd909]=5'b00100;glyph_mem[10'd910]=5'b01110;
        glyph_mem[10'd912]=5'b01110;glyph_mem[10'd913]=5'b10001;glyph_mem[10'd914]=5'b00001;glyph_mem[10'd915]=5'b00010;glyph_mem[10'd916]=5'b00100;glyph_mem[10'd917]=5'b01000;glyph_mem[10'd918]=5'b11111;
        glyph_mem[10'd920]=5'b11110;glyph_mem[10'd921]=5'b00001;glyph_mem[10'd922]=5'b00001;glyph_mem[10'd923]=5'b01110;glyph_mem[10'd924]=5'b00001;glyph_mem[10'd925]=5'b00001;glyph_mem[10'd926]=5'b11110;
        glyph_mem[10'd928]=5'b00010;glyph_mem[10'd929]=5'b00110;glyph_mem[10'd930]=5'b01010;glyph_mem[10'd931]=5'b10010;glyph_mem[10'd932]=5'b11111;glyph_mem[10'd933]=5'b00010;glyph_mem[10'd934]=5'b00010;
        glyph_mem[10'd936]=5'b11111;glyph_mem[10'd937]=5'b10000;glyph_mem[10'd938]=5'b10000;glyph_mem[10'd939]=5'b11110;glyph_mem[10'd940]=5'b00001;glyph_mem[10'd941]=5'b00001;glyph_mem[10'd942]=5'b11110;
        glyph_mem[10'd944]=5'b01110;glyph_mem[10'd945]=5'b10000;glyph_mem[10'd946]=5'b10000;glyph_mem[10'd947]=5'b11110;glyph_mem[10'd948]=5'b10001;glyph_mem[10'd949]=5'b10001;glyph_mem[10'd950]=5'b01110;
        glyph_mem[10'd952]=5'b11111;glyph_mem[10'd953]=5'b00001;glyph_mem[10'd954]=5'b00010;glyph_mem[10'd955]=5'b00100;glyph_mem[10'd956]=5'b01000;glyph_mem[10'd957]=5'b01000;glyph_mem[10'd958]=5'b01000;
        glyph_mem[10'd960]=5'b01110;glyph_mem[10'd961]=5'b10001;glyph_mem[10'd962]=5'b10001;glyph_mem[10'd963]=5'b01110;glyph_mem[10'd964]=5'b10001;glyph_mem[10'd965]=5'b10001;glyph_mem[10'd966]=5'b01110;
        glyph_mem[10'd968]=5'b01110;glyph_mem[10'd969]=5'b10001;glyph_mem[10'd970]=5'b10001;glyph_mem[10'd971]=5'b01111;glyph_mem[10'd972]=5'b00001;glyph_mem[10'd973]=5'b00001;glyph_mem[10'd974]=5'b01110;
        glyph_mem[10'd976]=5'b01110;glyph_mem[10'd977]=5'b10001;glyph_mem[10'd978]=5'b10001;glyph_mem[10'd979]=5'b11111;glyph_mem[10'd980]=5'b10001;glyph_mem[10'd981]=5'b10001;glyph_mem[10'd982]=5'b10001;
        glyph_mem[10'd984]=5'b11110;glyph_mem[10'd985]=5'b10001;glyph_mem[10'd986]=5'b10001;glyph_mem[10'd987]=5'b11110;glyph_mem[10'd988]=5'b10001;glyph_mem[10'd989]=5'b10001;glyph_mem[10'd990]=5'b11110;
        glyph_mem[10'd992]=5'b01111;glyph_mem[10'd993]=5'b10000;glyph_mem[10'd994]=5'b10000;glyph_mem[10'd995]=5'b10000;glyph_mem[10'd996]=5'b10000;glyph_mem[10'd997]=5'b10000;glyph_mem[10'd998]=5'b01111;
        glyph_mem[10'd1000]=5'b11110;glyph_mem[10'd1001]=5'b10001;glyph_mem[10'd1002]=5'b10001;glyph_mem[10'd1003]=5'b10001;glyph_mem[10'd1004]=5'b10001;glyph_mem[10'd1005]=5'b10001;glyph_mem[10'd1006]=5'b11110;
        glyph_mem[10'd1008]=5'b11111;glyph_mem[10'd1009]=5'b10000;glyph_mem[10'd1010]=5'b10000;glyph_mem[10'd1011]=5'b11110;glyph_mem[10'd1012]=5'b10000;glyph_mem[10'd1013]=5'b10000;glyph_mem[10'd1014]=5'b11111;
        glyph_mem[10'd1016]=5'b11111;glyph_mem[10'd1017]=5'b10000;glyph_mem[10'd1018]=5'b10000;glyph_mem[10'd1019]=5'b11110;glyph_mem[10'd1020]=5'b10000;glyph_mem[10'd1021]=5'b10000;glyph_mem[10'd1022]=5'b10000;
    end

    reg [9:0] glyph_addr;
    reg [2:0] text_column_d;
    reg text_active_d;
    reg [23:0] text_color_d,base_rgb_d;

    always @(*) begin
        glyph_addr=0;text_column_d=0;text_active_d=0;text_color_d=SAFE_TEXT;
        if(safe_active && safe_title_text) begin
            glyph_addr={3'd1,region_x_q[7:4],region_y_q[4:2]};
            text_column_d=region_x_q[3:1];text_active_d=region_x_q[3:0]<4'd10;
            text_color_d=SAFE_TEXT;
        end else if(safe_active && safe_state_text) begin
            glyph_addr={recovering ? 3'd3 : 3'd2,region_x_q[7:4],region_y_q[4:2]};
            text_column_d=region_x_q[3:1];text_active_d=region_x_q[3:0]<4'd10;
            text_color_d=recovering ? RECOVER_TEXT : SAFE_ACCENT;
        end else if(safe_active && safe_error_text) begin
            glyph_addr={3'd4,region_x_q[7:4],region_y_q[4:2]};
            if(region_x_q[7:4]==4'd11)
                glyph_addr={3'd7,error_code[7:4],region_y_q[4:2]};
            else if(region_x_q[7:4]==4'd12)
                glyph_addr={3'd7,error_code[3:0],region_y_q[4:2]};
            text_column_d=region_x_q[3:1];text_active_d=region_x_q[3:0]<4'd10;
            text_color_d=SAFE_ACCENT;
        end else if(degraded_active && degraded_text) begin
            glyph_addr={region_y_q[4] ? 3'd6 : 3'd5,region_x_q[6:3],region_y_q[3:1]};
            text_column_d=region_x_q[2:0];text_active_d=region_x_q[2:0]<3'd5;
            text_color_d=DEGRADED_TEXT;
        end
    end

    always @(*) begin
        base_rgb_d=region_rgb_q;
        if(safe_active && in_canvas) begin
            base_rgb_d=region_x_q[6]^region_y_q[6] ? SAFE_BG_B : SAFE_BG_A;
            if(safe_center_panel) base_rgb_d=SAFE_PANEL;
            if(safe_border || (!(|region_x_q[14:5]) && region_x_q[4:3]<2'd3))
                base_rgb_d=recovering ? RECOVER_RAIL : SAFE_RAIL;
        end else if(degraded_active && degraded_panel)
            base_rgb_d=degraded_border ? DEGRADED_BORDER : DEGRADED_BG;
    end

    reg packet_valid_q,packet_user_q,packet_last_q;
    reg [14:0] packet_x_q,packet_y_q;
    reg [23:0] base_rgb_q,text_color_q;
    reg [2:0] text_column_q;
    reg text_active_q,glyph_on_q;
    reg [4:0] glyph_bits_q;
    always @(posedge clk) glyph_bits_q<=glyph_mem[glyph_addr];
    always @(*) begin
        case(text_column_q)
            3'd0:glyph_on_q=glyph_bits_q[4];3'd1:glyph_on_q=glyph_bits_q[3];
            3'd2:glyph_on_q=glyph_bits_q[2];3'd3:glyph_on_q=glyph_bits_q[1];
            3'd4:glyph_on_q=glyph_bits_q[0];default:glyph_on_q=0;
        endcase
    end

    always @(posedge clk or posedge rst) begin
        if(rst) begin
            failsafe_state_q<=0;health_status_q<=0;error_code_q<=0;
            region_valid_q<=0;region_user_q<=0;region_last_q<=0;
            region_x_q<=0;region_y_q<=0;region_rgb_q<=0;
            packet_valid_q<=0;packet_user_q<=0;packet_last_q<=0;
            packet_x_q<=0;packet_y_q<=0;base_rgb_q<=0;text_color_q<=0;
            text_column_q<=0;text_active_q<=0;
            out_valid<=0;out_user<=0;out_last<=0;out_x<=0;out_y<=0;out_rgb<=0;
        end else begin
            if(first) begin
                failsafe_state_q<=failsafe_state_pending;
                health_status_q<=health_status_pending;
                error_code_q<=error_code_pending;
            end
            region_valid_q<=in_valid;region_user_q<=in_user;region_last_q<=in_last;
            region_x_q<=in_x;region_y_q<=in_y;region_rgb_q<=in_rgb;
            packet_valid_q<=region_valid_q;packet_user_q<=region_user_q;
            packet_last_q<=region_last_q;
            packet_x_q<=region_x_q;packet_y_q<=region_y_q;base_rgb_q<=base_rgb_d;
            text_color_q<=text_color_d;text_column_q<=text_column_d;
            text_active_q<=text_active_d;
            out_valid<=packet_valid_q;out_user<=packet_user_q;out_last<=packet_last_q;
            out_x<=packet_x_q;out_y<=packet_y_q;
            out_rgb<=text_active_q && glyph_on_q ? text_color_q : base_rgb_q;
        end
    end
endmodule
