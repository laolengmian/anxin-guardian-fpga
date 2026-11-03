// Derived from the 2026 lab_ex5_i2s lane_lvds_10_1 implementation.
// Independent pixel/serial resets and serial-register reset coverage are local changes.
module lane_lvds_10_1_hardened #(
    parameter DEVICE = "EG"
) (
    input wire I_pixel_clk,
    input wire I_serial_clk,
    input wire I_pixel_rst,
    input wire I_serial_rst,
    input wire [9:0] I_data_in,
    output wire O_serial_out
);

reg S_odd_even;
(* ASYNC_REG = "TRUE" *) reg S_odd_even_1d;
(* ASYNC_REG = "TRUE" *) reg S_odd_even_2d;
reg S_load_en;
reg S_load_en_1d;
reg S_load_en_2d;
reg [9:0] S_shift_data;
reg [1:0] S_oddr_data;

always @(posedge I_pixel_clk or posedge I_pixel_rst) begin
    if (I_pixel_rst)
        S_odd_even <= 1'b0;
    else
        S_odd_even <= ~S_odd_even;
end

always @(posedge I_serial_clk or posedge I_serial_rst) begin
    if (I_serial_rst) begin
        S_odd_even_1d <= 1'b0;
        S_odd_even_2d <= 1'b0;
        S_load_en <= 1'b0;
        S_load_en_1d <= 1'b0;
        S_load_en_2d <= 1'b0;
        S_shift_data <= 10'd0;
        S_oddr_data <= 2'd0;
    end else begin
        S_odd_even_1d <= S_odd_even;
        S_odd_even_2d <= S_odd_even_1d;
        S_load_en <= S_odd_even_1d ^ S_odd_even_2d;
        S_load_en_1d <= S_load_en;
        S_load_en_2d <= S_load_en_1d;

        if (S_load_en_2d)
            S_shift_data <= I_data_in;
        else
            S_shift_data <= S_shift_data << 2;

        S_oddr_data <= S_shift_data[9:8];
    end
end

generate
    if (DEVICE == "EG") begin : g_eg_oddr
        EG_LOGIC_ODDR u_oddr (
            .clk(I_serial_clk),
            .rst(I_serial_rst),
            .d1(S_oddr_data[0]),
            .d0(S_oddr_data[1]),
            .q(O_serial_out)
        );
    end
endgenerate

endmodule
