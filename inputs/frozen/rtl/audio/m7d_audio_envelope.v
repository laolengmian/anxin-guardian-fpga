// True final-PCM envelope: 240 valid samples per point, 256-point history.
// Capture and display share clk in the current 75 MHz integration; no CDC here.
module m7d_audio_envelope (
    input wire clk,input wire rst,input wire sample_valid,
    input wire signed [15:0] sample_pcm,input wire [7:0] read_addr,
    output reg [47:0] read_data,output reg [7:0] write_ptr,
    output reg [8:0] point_count,output reg point_commit,
    output reg [15:0] latest_peak
);
    localparam integer WINDOW_SAMPLES=240;
    (* ram_style="block" *) reg [47:0] mem [0:255];
    reg [7:0] window_count;
    reg signed [15:0] min_q,max_q;
    reg [15:0] peak_q;
    wire [15:0] sample_abs=sample_pcm[15] ? (~sample_pcm+16'd1) : sample_pcm;
    wire signed [15:0] next_min=(window_count==0 || sample_pcm<min_q) ? sample_pcm : min_q;
    wire signed [15:0] next_max=(window_count==0 || sample_pcm>max_q) ? sample_pcm : max_q;
    wire [15:0] next_peak=(window_count==0 || sample_abs>peak_q) ? sample_abs : peak_q;
    always @(posedge clk or posedge rst) begin
        if(rst) begin
            read_data<=0;write_ptr<=0;point_count<=0;point_commit<=0;
            latest_peak<=0;window_count<=0;min_q<=0;max_q<=0;peak_q<=0;
        end else begin
            read_data<=mem[read_addr];
            point_commit<=0;
            if(sample_valid) begin
                if(window_count==WINDOW_SAMPLES-1) begin
                    mem[write_ptr]<={next_min,next_max,next_peak};
                    write_ptr<=write_ptr+1'b1;
                    if(point_count<9'd256) point_count<=point_count+1'b1;
                    latest_peak<=next_peak;
                    point_commit<=1;
                    window_count<=0;min_q<=0;max_q<=0;peak_q<=0;
                end else begin
                    min_q<=next_min;max_q<=next_max;peak_q<=next_peak;
                    window_count<=window_count+1'b1;
                end
            end
        end
    end
endmodule
