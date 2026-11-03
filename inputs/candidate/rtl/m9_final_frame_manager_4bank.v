`timescale 1ns/1ps

// Candidate-local hardening of the accepted four-bank scheduler. The load and

// round-robin policy is unchanged. A video-only reset quarantines and cancels an

// uncommitted request without resetting the visible bank or replaying a toggle.

`include "global_def.v"



module m9_final_frame_manager_4bank (

    input wire sys_clk,input wire sys_rst_n,

    input wire next_image_req,input wire auto_play_enable,

    input wire [31:0] auto_period_cycles,

    input wire [3:0] bank_load_complete,input wire [3:0] bank_load_error,

    output reg [1:0] next_load_bank,output reg start_load,

    input wire video_clk,input wire video_rst_n,input wire video_epoch_rst_n,input wire bank_commit_trig,

    output reg [1:0] display_bank,output reg bank_switch_commit,

    output reg switch_complete_sys,

    output wire [1:0] bank0_state,bank1_state,bank2_state,bank3_state,

    output wire [31:0] bank0_base_addr,bank1_base_addr,bank2_base_addr,bank3_base_addr

);

    assign bank0_base_addr=`BANK0_BASE;

    assign bank1_base_addr=`BANK1_BASE;

    assign bank2_base_addr=`BANK2_BASE;

    assign bank3_base_addr=`BANK3_BASE;



    reg [1:0] bank_state [0:3];

    assign bank0_state=bank_state[0];

    assign bank1_state=bank_state[1];

    assign bank2_state=bank_state[2];

    assign bank3_state=bank_state[3];



    reg [31:0] auto_counter;

    reg auto_trigger;

    always @(posedge sys_clk or negedge sys_rst_n) begin

        if(!sys_rst_n) begin

            auto_counter<=32'd0;

            auto_trigger<=1'b0;

        end else begin

            auto_trigger<=1'b0;

            if(auto_play_enable) begin

                if(auto_counter>=auto_period_cycles-1) begin

                    auto_counter<=32'd0;

                    auto_trigger<=1'b1;

                end else

                    auto_counter<=auto_counter+1'b1;

            end else

                auto_counter<=32'd0;

        end

    end



    reg [1:0] pending_display_bank;

    reg display_request_toggle;

    reg [1:0] prev_display_bank;

    wire [1:0] rr_next1=prev_display_bank+2'd1;

    wire [1:0] rr_next2=prev_display_bank+2'd2;

    wire [1:0] rr_next3=prev_display_bank+2'd3;

    wire next_trigger=next_image_req|auto_trigger;



    always @(posedge sys_clk or negedge sys_rst_n) begin

        if(!sys_rst_n) begin

            pending_display_bank<=2'd0;

            display_request_toggle<=1'b0;

        end else if(next_trigger) begin

            if(bank_state[rr_next1]==`BANK_STATE_READY) begin

                pending_display_bank<=rr_next1;

                display_request_toggle<=~display_request_toggle;

            end else if(bank_state[rr_next2]==`BANK_STATE_READY) begin

                pending_display_bank<=rr_next2;

                display_request_toggle<=~display_request_toggle;

            end else if(bank_state[rr_next3]==`BANK_STATE_READY) begin

                pending_display_bank<=rr_next3;

                display_request_toggle<=~display_request_toggle;

            end

        end

    end



    wire any_loading=(bank_state[0]==`BANK_STATE_LOADING)||

                     (bank_state[1]==`BANK_STATE_LOADING)||

                     (bank_state[2]==`BANK_STATE_LOADING)||

                     (bank_state[3]==`BANK_STATE_LOADING);

    reg [1:0] first_idle_bank;

    reg has_idle_bank;

    integer j;

    always @* begin

        first_idle_bank=2'd0;

        has_idle_bank=1'b0;

        for(j=3;j>=0;j=j-1) begin

            if(bank_state[j]==`BANK_STATE_IDLE) begin

                first_idle_bank=j[1:0];

                has_idle_bank=1'b1;

            end

        end

    end



    (* ASYNC_REG = "TRUE" *) reg ack_sync1,ack_sync2;

    reg ack_seen_sys;

    (* ASYNC_REG = "TRUE" *) reg cancel_sync1,cancel_sync2;

    (* ASYNC_REG = "TRUE" *) reg req_toggle_sync1,req_toggle_sync2;

    reg req_seen_video;

    reg [1:0] pending_bank_sync1,pending_bank_sync2,requested_bank_video;

    reg request_token_video,commit_pending,payload_capture_pending;

    reg [1:0] payload_settle_count;

    reg ack_toggle_video,ack_cancel_video;

    reg cancel_ack_pending,cancel_token_video;

    reg [1:0] cancel_ack_delay,normal_ack_delay;

    reg [1:0] reset_quarantine;

    integer i;



    always @(posedge sys_clk or negedge sys_rst_n) begin

        if(!sys_rst_n) begin

            for(i=0;i<4;i=i+1)

                bank_state[i]<=`BANK_STATE_IDLE;

            next_load_bank<=2'd0;

            start_load<=1'b0;

            ack_sync1<=1'b0;

            ack_sync2<=1'b0;

            ack_seen_sys<=1'b0;

            cancel_sync1<=1'b0;

            cancel_sync2<=1'b0;

            prev_display_bank<=2'd0;

            switch_complete_sys<=1'b0;

        end else begin

            start_load<=1'b0;

            switch_complete_sys<=1'b0;

            ack_sync1<=ack_toggle_video;

            ack_sync2<=ack_sync1;

            cancel_sync1<=ack_cancel_video;

            cancel_sync2<=cancel_sync1;



            for(i=0;i<4;i=i+1) begin

                case(bank_state[i])

                    `BANK_STATE_IDLE: begin

                        if(!any_loading && has_idle_bank && i==first_idle_bank) begin

                            bank_state[i]<=`BANK_STATE_LOADING;

                            next_load_bank<=i[1:0];

                            start_load<=1'b1;

                        end

                    end

                    `BANK_STATE_LOADING: begin

                        if(bank_load_complete[i])

                            bank_state[i]<=`BANK_STATE_READY;

                        else if(bank_load_error[i])

                            bank_state[i]<=`BANK_STATE_IDLE;

                    end

                    default: begin end

                endcase

            end



            if(ack_sync2!=ack_seen_sys) begin

                ack_seen_sys<=ack_sync2;

                if(cancel_sync2) begin

                    // Cancellation acknowledges only the transaction token.

                    // Visible ownership and round-robin state remain unchanged.

                end else begin

                    if(bank_state[prev_display_bank]==`BANK_STATE_DISPLAY)

                        bank_state[prev_display_bank]<=`BANK_STATE_READY;

                    if(bank_state[pending_display_bank]==`BANK_STATE_READY)

                        bank_state[pending_display_bank]<=`BANK_STATE_DISPLAY;

                    prev_display_bank<=pending_display_bank;

                    switch_complete_sys<=1'b1;

                end

            end

        end

    end



    // Resettable capture state. Four post-reset video clocks align to the live

    // source token; an event already in flight at reset is treated as canceled.

    always @(posedge video_clk or negedge video_rst_n or negedge video_epoch_rst_n) begin

        if(!video_rst_n || !video_epoch_rst_n) begin

            req_toggle_sync1<=1'b0;

            req_toggle_sync2<=1'b0;

            pending_bank_sync1<=2'd0;

            pending_bank_sync2<=2'd0;

            req_seen_video<=1'b0;

            requested_bank_video<=2'd0;

            request_token_video<=1'b0;

            commit_pending<=1'b0;

            payload_capture_pending<=1'b0;

            payload_settle_count<=2'd0;

            bank_switch_commit<=1'b0;

            normal_ack_delay<=2'd0;

            reset_quarantine<=2'd0;

        end else begin

            req_toggle_sync1<=display_request_toggle;

            req_toggle_sync2<=req_toggle_sync1;

            pending_bank_sync1<=pending_display_bank;

            pending_bank_sync2<=pending_bank_sync1;

            bank_switch_commit<=1'b0;



            if(reset_quarantine!=2'd3) begin

                reset_quarantine<=reset_quarantine+1'b1;

                req_seen_video<=req_toggle_sync2;

                commit_pending<=1'b0;

                payload_capture_pending<=1'b0;

                payload_settle_count<=2'd0;

                normal_ack_delay<=2'd0;

            end else begin

                if(req_toggle_sync2!=req_seen_video && !commit_pending &&

                   !payload_capture_pending) begin

                    req_seen_video<=req_toggle_sync2;

                    request_token_video<=req_toggle_sync2;

                    payload_capture_pending<=1'b1;

                    payload_settle_count<=2'd0;

                end else if(payload_capture_pending) begin

                    if(payload_settle_count==2'd2) begin

                        requested_bank_video<=pending_bank_sync2;

                        payload_capture_pending<=1'b0;

                        payload_settle_count<=2'd0;

                        commit_pending<=1'b1;

                        normal_ack_delay<=2'd0;

                    end else

                        payload_settle_count<=payload_settle_count+1'b1;

                end else if(commit_pending && normal_ack_delay!=2'd2) begin

                    normal_ack_delay<=normal_ack_delay+1'b1;

                end

                if(bank_commit_trig && commit_pending && normal_ack_delay==2'd2) begin

                    commit_pending<=1'b0;

                    normal_ack_delay<=2'd0;

                    bank_switch_commit<=1'b1;

                end

            end

        end

    end



    // Visible ownership and acknowledgement survive video-only reset. The

    // cancellation flag is a held payload: it settles for three video clocks

    // before the acknowledgement token changes. A fresh request clears it and

    // likewise waits before a normal acknowledgement can change.

    always @(posedge video_clk or negedge video_epoch_rst_n) begin

        if(!video_epoch_rst_n) begin

            display_bank<=2'd0;

            ack_toggle_video<=1'b0;

            ack_cancel_video<=1'b0;

            cancel_ack_pending<=1'b0;

            cancel_token_video<=1'b0;

            cancel_ack_delay<=2'd0;

        end else if(!video_rst_n) begin

            cancel_ack_pending<=1'b0;

            cancel_ack_delay<=2'd0;

        end else if(reset_quarantine==2'd2 &&

                    req_toggle_sync2!=ack_toggle_video && !cancel_ack_pending) begin

            ack_cancel_video<=1'b1;

            cancel_token_video<=req_toggle_sync2;

            cancel_ack_pending<=1'b1;

            cancel_ack_delay<=2'd0;

        end else if(cancel_ack_pending) begin

            if(cancel_ack_delay==2'd2) begin

                ack_toggle_video<=cancel_token_video;

                cancel_ack_pending<=1'b0;

                cancel_ack_delay<=2'd0;

            end else

                cancel_ack_delay<=cancel_ack_delay+1'b1;

        end else if(reset_quarantine==2'd3 &&

                    req_toggle_sync2!=req_seen_video && !commit_pending &&

                    !payload_capture_pending) begin

            ack_cancel_video<=1'b0;

        end else if(reset_quarantine==2'd3 && bank_commit_trig &&

                    commit_pending && normal_ack_delay==2'd2) begin

            display_bank<=requested_bank_video;

            ack_toggle_video<=request_token_video;

            ack_cancel_video<=1'b0;

        end

    end

endmodule

