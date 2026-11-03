// M9 target-initiated stable multi-bit snapshot. Control toggles use 2FF
// synchronizers; the source-held payload settles through two destination stages.
module m9_cdc_snapshot #(
    parameter integer WIDTH=10
) (
    input wire dst_clk,input wire dst_rst,input wire dst_request,
    output reg dst_busy,output reg dst_valid,output reg [WIDTH-1:0] dst_data,
    input wire src_clk,input wire src_rst,input wire [WIDTH-1:0] src_data
);
    reg request_toggle;
    (* ASYNC_REG="TRUE" *) reg src_request_sync_stage1;
    (* ASYNC_REG="TRUE" *) reg src_request_sync_stage2;
    reg src_ack_toggle;
    reg [WIDTH-1:0] src_held_data;
    reg [1:0] src_init_count;
    reg src_ready;

    (* ASYNC_REG="TRUE" *) reg ack_sync_stage1;
    (* ASYNC_REG="TRUE" *) reg ack_sync_stage2;
    (* ASYNC_REG="TRUE" *) reg src_ready_sync_stage1;
    (* ASYNC_REG="TRUE" *) reg src_ready_sync_stage2;
    wire [WIDTH-1:0] payload_sync_stage2;
    reg [1:0] dst_init_count;
    // Confirmation window lets synchronized src_ready cancel a completion if
    // the source resets after capture. Qualified source resets span this window.
    reg [1:0] ack_confirm_count;
    reg initialized;
    reg retry_pending;

    genvar payload_bit;
    generate
        for(payload_bit=0;payload_bit<WIDTH;payload_bit=payload_bit+1) begin: g_payload_sync
            cdc_bit_sync u_payload_sync (
                .clk_dst(dst_clk),.rst_dst(dst_rst),
                .async_in(src_held_data[payload_bit]),
                .sync_out(payload_sync_stage2[payload_bit])
            );
        end
    endgenerate

    always @(posedge src_clk or posedge src_rst) begin
        if(src_rst) begin
            src_request_sync_stage1<=0;
            src_request_sync_stage2<=0;
            src_ack_toggle<=0;
            src_held_data<=0;
            src_init_count<=0;
            src_ready<=0;
        end else begin
            src_request_sync_stage1<=request_toggle;
            src_request_sync_stage2<=src_request_sync_stage1;
            if(!src_ready) begin
                if(src_init_count==2'd3) src_ready<=1;
                else src_init_count<=src_init_count+1'b1;
            end else if(src_request_sync_stage2!=src_ack_toggle) begin
                src_held_data<=src_data;
                src_ack_toggle<=src_request_sync_stage2;
            end
        end
    end

    always @(posedge dst_clk or posedge dst_rst) begin
        if(dst_rst) begin
            request_toggle<=0;
            ack_sync_stage1<=0;
            ack_sync_stage2<=0;
            src_ready_sync_stage1<=0;
            src_ready_sync_stage2<=0;
            dst_init_count<=0;
            ack_confirm_count<=0;
            initialized<=0;
            retry_pending<=0;
            dst_busy<=1;
            dst_valid<=0;
            dst_data<=0;
        end else begin
            ack_sync_stage1<=src_ack_toggle;
            ack_sync_stage2<=ack_sync_stage1;
            src_ready_sync_stage1<=src_ready;
            src_ready_sync_stage2<=src_ready_sync_stage1;
            dst_valid<=0;
            if(!src_ready_sync_stage2) begin
                if((initialized && dst_busy) || dst_request) retry_pending<=1;
                dst_init_count<=0;
                ack_confirm_count<=0;
                initialized<=0;
                dst_busy<=1;
            end else if(!initialized) begin
                ack_confirm_count<=0;
                dst_busy<=1;
                if(dst_init_count==2'd3) begin
                    initialized<=1;
                    if(retry_pending) begin
                        request_toggle<=~ack_sync_stage2;
                        retry_pending<=0;
                    end else begin
                        request_toggle<=ack_sync_stage2;
                        dst_busy<=0;
                    end
                end else begin
                    dst_init_count<=dst_init_count+1'b1;
                end
            end else if(dst_busy) begin
                if(ack_sync_stage2!=request_toggle) begin
                    ack_confirm_count<=0;
                end else if(ack_confirm_count==2'd2) begin
                    dst_data<=payload_sync_stage2;
                    dst_valid<=1;
                    dst_busy<=0;
                    ack_confirm_count<=0;
                end else begin
                    ack_confirm_count<=ack_confirm_count+1'b1;
                end
            end else if(dst_request) begin
                request_toggle<=~request_toggle;
                dst_busy<=1;
                ack_confirm_count<=0;
            end else begin
                ack_confirm_count<=0;
            end
        end
    end
endmodule
