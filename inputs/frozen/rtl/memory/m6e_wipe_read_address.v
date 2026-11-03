// M6-E: burst-aligned top-to-bottom wipe over immutable resident frames.
// mem_clk only. Keep App_rd_en, its timing, refresh admission and response FIFO
// untouched; substitute addresses using two pointers with the same word offset.
// read_ack falls after the official reader has latched its session base, before
// its first read command. Progress advances only after a complete prior session.
module m6e_wipe_read_address #(
    parameter integer FRAME_WORDS = 460800,
    parameter integer STEP_WORDS = 15360
) (
    input wire mem_clk,
    input wire rst,
    input wire read_ack,
    input wire app_en,
    input wire [20:0] app_addr,
    output wire [20:0] mapped_addr,
    output reg [1:0] image_bank,
    output reg status_event
);
    reg ack_q, initialized;
    reg [1:0] settled_bank, target_bank;
    reg [20:0] cutoff, issued_words;
    reg [20:0] old_pointer, new_pointer, new_remaining;
    wire session_start = ack_q && !read_ack;
    wire completed = issued_words == FRAME_WORDS;

    function [20:0] bank_base;
        input [1:0] bank;
        begin
            case(bank)
                0: bank_base=21'h000000;
                1: bank_base=21'h070800;
                2: bank_base=21'h0e1000;
                3: bank_base=21'h151800;
            endcase
        end
    endfunction

    // The address is a base, not an arbitrary live read address, when sampled.
    wire [1:0] requested_bank = app_addr==21'h070800 ? 2'd1 :
                                app_addr==21'h0e1000 ? 2'd2 :
                                app_addr==21'h151800 ? 2'd3 : 2'd0;

    reg [1:0] settled_next, target_next;
    reg [20:0] cutoff_next;
    always @(*) begin
        settled_next=settled_bank;
        target_next=target_bank;
        cutoff_next=cutoff;
        if(!initialized) begin
            settled_next=requested_bank;
            target_next=requested_bank;
            cutoff_next=0;
        end else if(completed) begin
            if(cutoff==0 || cutoff==FRAME_WORDS) begin
                if(cutoff==FRAME_WORDS) settled_next=target_bank;
                target_next=requested_bank;
                cutoff_next=(requested_bank==settled_next) ? 0 : STEP_WORDS;
            end else if(cutoff>=FRAME_WORDS-STEP_WORDS) begin
                cutoff_next=FRAME_WORDS;
            end else begin
                cutoff_next=cutoff+STEP_WORDS;
            end
        end
    end

    assign mapped_addr = (new_remaining!=0) ? new_pointer : old_pointer;
    always @(posedge mem_clk or posedge rst) begin
        if(rst) begin
            ack_q<=0; initialized<=0;
            settled_bank<=0; target_bank<=0; cutoff<=0; issued_words<=0;
            old_pointer<=0; new_pointer<=0; new_remaining<=0;
            image_bank<=0; status_event<=0;
        end else begin
            ack_q<=read_ack;
            status_event<=0;
            if(session_start) begin
                initialized<=1;
                settled_bank<=settled_next;
                target_bank<=target_next;
                cutoff<=cutoff_next;
                old_pointer<=bank_base(settled_next);
                new_pointer<=bank_base(target_next);
                new_remaining<=cutoff_next;
                issued_words<=0;
                image_bank<=target_next;
                status_event<=1;
            end else if(app_en) begin
                old_pointer<=old_pointer+1'b1;
                new_pointer<=new_pointer+1'b1;
                issued_words<=issued_words+1'b1;
                if(new_remaining!=0) new_remaining<=new_remaining-1'b1;
            end
        end
    end
endmodule
