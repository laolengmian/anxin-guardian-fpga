// One-way physical reader ownership after immutable image preload completes.
// The quiet window includes requests/responses, not just reader_busy, so a
// request awaiting physical acceptance is not mistaken for an idle reader.
module m7b_sd_handoff (
    input wire clk, input wire rst_n, input wire images_done,
    input wire reader_busy, input wire reader_valid, input wire reader_done,
    input wire image_req, output reg audio_owner, output reg audio_start
);
    reg pending;
    reg [5:0] quiet_count;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            pending<=0;quiet_count<=0;audio_owner<=0;audio_start<=0;
        end else begin
            audio_start<=0;
            if(images_done) pending<=1;
            if(!audio_owner && pending) begin
                if(reader_busy || reader_valid || reader_done || image_req)
                    quiet_count<=0;
                else if(quiet_count==31) begin
                    audio_owner<=1;audio_start<=1;
                end else quiet_count<=quiet_count+1'b1;
            end
        end
    end
endmodule
