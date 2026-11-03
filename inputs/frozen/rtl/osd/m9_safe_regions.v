// Synchronous coordinate membership ROMs for exact SAFE/DEGRADED rectangles.
// The renderer delays the complete input packet by the same lookup cycle.
module m9_safe_regions (
    input wire clk,input wire [14:0] in_x,input wire [14:0] in_y,
    output wire in_canvas,output wire safe_border,output wire safe_center_panel,
    output wire degraded_panel,output wire degraded_border,
    output wire safe_title_text,output wire safe_state_text,
    output wire safe_error_text,output wire degraded_text
);
    reg [9:0] x_membership_mem [0:2047] /* fehdl force_ram=1, ram_style="bram" */;
    reg [9:0] y_membership_mem [0:1023] /* fehdl force_ram=1, ram_style="bram" */;
    reg [9:0] x_membership,y_membership;
    reg x_bounded,y_bounded;
    integer init_x,init_y;
    initial begin
        for(init_x=0;init_x<2048;init_x=init_x+1)
            x_membership_mem[init_x]={
                init_x>=24 && init_x<88,
                init_x>=560 && init_x<720,
                init_x>=528 && init_x<736,
                init_x>=544 && init_x<720,
                init_x>=12 && init_x<148,
                init_x>=8 && init_x<152,
                init_x>=480 && init_x<800,
                init_x>=40 && init_x<1240,
                init_x>=32 && init_x<1248,
                init_x<1280};
        for(init_y=0;init_y<1024;init_y=init_y+1)
            y_membership_mem[init_y]={
                (init_y>=64 && init_y<78)||(init_y>=80 && init_y<94),
                init_y>=416 && init_y<444,
                init_y>=288 && init_y<316,
                init_y>=160 && init_y<188,
                init_y>=60 && init_y<108,
                init_y>=56 && init_y<112,
                init_y>=112 && init_y<480,
                init_y>=40 && init_y<680,
                init_y>=32 && init_y<688,
                init_y<720};
    end
    always @(posedge clk) begin
        x_membership<=x_membership_mem[in_x[10:0]];
        y_membership<=y_membership_mem[in_y[9:0]];
        x_bounded<=!(|in_x[14:11]);
        y_bounded<=!(|in_y[14:10]);
    end
    wire bounded=x_bounded && y_bounded;
    assign in_canvas=bounded && x_membership[0] && y_membership[0];
    assign safe_border=bounded && x_membership[1] && y_membership[1] &&
        !(x_membership[2] && y_membership[2]);
    assign safe_center_panel=bounded && x_membership[3] && y_membership[3];
    assign degraded_panel=bounded && x_membership[4] && y_membership[4];
    assign degraded_border=degraded_panel &&
        !(x_membership[5] && y_membership[5]);
    assign safe_title_text=bounded && x_membership[6] && y_membership[6];
    assign safe_state_text=bounded && x_membership[7] && y_membership[7];
    assign safe_error_text=bounded && x_membership[8] && y_membership[8];
    assign degraded_text=bounded && x_membership[9] && y_membership[9];
endmodule
