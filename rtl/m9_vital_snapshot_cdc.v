`timescale 1ns/1ps
// Held-payload absolute-state transfer with reset-coherent request epochs.
// A remote reset asserts a local quarantine asynchronously and releases it only
// through two local clocks, so reset and request tokens cannot reconverge out of
// order. Payload is sampled only after the synchronized token settles.
module m9_vital_snapshot_cdc #(parameter integer WIDTH=65) (
    input wire src_clk,input wire src_rst,
    input wire [WIDTH-1:0] src_data,input wire src_update,output reg src_busy,
    input wire dst_clk,input wire dst_rst,input wire dst_commit,
    output reg [WIDTH-1:0] dst_data,output reg dst_update
);
    reg [WIDTH-1:0] payload,pending_payload;
    reg pending,request_toggle,force_transfer;
    (* ASYNC_REG = "TRUE" *) reg ack_sync1,ack_sync2;
    reg ack_seen;
    wire ack_event=ack_sync2^ack_seen;

    (* ASYNC_REG = "TRUE" *) reg request_sync1,request_sync2;
    reg request_seen,capture_pending,capture_token;
    reg [1:0] payload_settle_count;
    reg [WIDTH-1:0] accepted_payload;
    reg accepted_pulse;

    // Remote-reset bridges: asynchronous assertion, local synchronous release.
    (* ASYNC_REG = "TRUE" *) reg dst_reset_src_sync1,dst_reset_src_sync2;
    (* ASYNC_REG = "TRUE" *) reg src_reset_dst_sync1,src_reset_dst_sync2;
    wire dst_reset_src=dst_reset_src_sync2;
    wire src_reset_dst=src_reset_dst_sync2;

    always @(posedge src_clk or posedge dst_rst) begin
        if(dst_rst) begin
            dst_reset_src_sync1<=1'b1;
            dst_reset_src_sync2<=1'b1;
        end else begin
            dst_reset_src_sync1<=1'b0;
            dst_reset_src_sync2<=dst_reset_src_sync1;
        end
    end

    always @(posedge dst_clk or posedge src_rst) begin
        if(src_rst) begin
            src_reset_dst_sync1<=1'b1;
            src_reset_dst_sync2<=1'b1;
        end else begin
            src_reset_dst_sync1<=1'b0;
            src_reset_dst_sync2<=src_reset_dst_sync1;
        end
    end

    always @(posedge src_clk or posedge src_rst or posedge dst_reset_src) begin
        if(src_rst || dst_reset_src) begin
            payload<={WIDTH{1'b0}};
            pending_payload<={WIDTH{1'b0}};
            pending<=1'b0;
            request_toggle<=1'b0;
            src_busy<=1'b0;
            force_transfer<=1'b1;
            ack_sync1<=1'b0;
            ack_sync2<=1'b0;
            ack_seen<=1'b0;
        end else begin
            ack_sync1<=request_seen;
            ack_sync2<=ack_sync1;
            ack_seen<=ack_sync2;
            if(force_transfer) begin
                payload<=src_data;
                request_toggle<=1'b1;
                src_busy<=1'b1;
                pending<=1'b0;
                force_transfer<=1'b0;
            end else if(ack_event) begin
                if(pending || src_update) begin
                    payload<=src_update ? src_data : pending_payload;
                    request_toggle<=~request_toggle;
                    pending<=1'b0;
                    src_busy<=1'b1;
                end else
                    src_busy<=1'b0;
            end else if(src_update) begin
                if(src_busy) begin
                    pending_payload<=src_data;
                    pending<=1'b1;
                end else begin
                    payload<=src_data;
                    request_toggle<=~request_toggle;
                    src_busy<=1'b1;
                end
            end
        end
    end

    // Protocol state is quarantined by either the local reset or the
    // synchronized remote-reset assertion. The output snapshot is also
    // cleared by a remote source reset so stale validity cannot survive reacquisition.
    always @(posedge dst_clk or posedge dst_rst or posedge src_reset_dst) begin
        if(dst_rst || src_reset_dst) begin
            request_sync1<=1'b0;
            request_sync2<=1'b0;
            request_seen<=1'b0;
            capture_pending<=1'b0;
            capture_token<=1'b0;
            payload_settle_count<=2'd0;
            accepted_payload<={WIDTH{1'b0}};
            accepted_pulse<=1'b0;
        end else begin
            request_sync1<=request_toggle;
            request_sync2<=request_sync1;
            accepted_pulse<=1'b0;
            if(!capture_pending && request_sync2!=request_seen) begin
                capture_pending<=1'b1;
                capture_token<=request_sync2;
                payload_settle_count<=2'd0;
            end else if(capture_pending && payload_settle_count!=2'd2) begin
                payload_settle_count<=payload_settle_count+1'b1;
            end else if(capture_pending && dst_commit) begin
                accepted_payload<=payload;
                accepted_pulse<=1'b1;
                request_seen<=capture_token;
                capture_pending<=1'b0;
                payload_settle_count<=2'd0;
            end
        end
    end

    always @(posedge dst_clk or posedge dst_rst or posedge src_reset_dst) begin
        if(dst_rst || src_reset_dst) begin
            dst_data<={WIDTH{1'b0}};
            dst_update<=src_reset_dst && !dst_rst;
        end else begin
            dst_update<=accepted_pulse;
            if(accepted_pulse)
                dst_data<=accepted_payload;
        end
    end
endmodule
