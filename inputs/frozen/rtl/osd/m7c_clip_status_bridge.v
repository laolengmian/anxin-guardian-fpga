// Latest-value metadata bridge. Payload remains held until request/ack completes.
module m7c_clip_status_bridge (
    input wire src_clk,input wire src_rst,input wire [1:0] src_clip,
    input wire dst_clk,input wire dst_rst,output wire [1:0] dst_clip
);
    reg sent_valid;
    reg [1:0] sent_clip;
    wire busy;
    wire request=!busy && (!sent_valid || sent_clip!=src_clip);
    always @(posedge src_clk or posedge src_rst) begin
        if(src_rst) begin sent_valid<=0;sent_clip<=0;end
        else if(request) begin sent_valid<=1;sent_clip<=src_clip;end
    end
    cdc_frame_commit u_commit(.src_clk(src_clk),.src_rst(src_rst),.src_request(request),
        .src_buf_idx(src_clip),.src_busy(busy),.src_ack_pulse(),.src_reject_pulse(),
        .dst_clk(dst_clk),.dst_rst(dst_rst),.frame_boundary(1'b1),
        .dst_commit_pulse(),.dst_buf_idx(dst_clip));
endmodule
