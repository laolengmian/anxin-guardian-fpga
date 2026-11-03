`timescale 1ns/1ps

// Two-key policy derived from the 米处 chord/long-hold router. Both inputs are
// active-low board keys. The chord is intentionally inert because M6-C is
// strictly read-only and has no save operation.
module m6c_key_router #(
    parameter integer DEBOUNCE_CYCLES = 1000000,
    parameter integer BRIGHTNESS_HOLD_CYCLES = 50000000
) (
    input  wire clk,
    input  wire rst_n,
    input  wire key_next_n,
    input  wire key_auto_n,
    output reg  next_event,
    output reg  auto_event,
    output reg  brightness_event,
    output reg  next_stable_n,
    output reg  auto_stable_n
);
    localparam [1:0] ST_IDLE  = 2'd0;
    localparam [1:0] ST_NEXT  = 2'd1;
    localparam [1:0] ST_AUTO  = 2'd2;
    localparam [1:0] ST_CHORD = 2'd3;

    localparam integer DB_BITS =
        (DEBOUNCE_CYCLES <= 1) ? 1 : $clog2(DEBOUNCE_CYCLES);
    localparam integer HOLD_BITS =
        (BRIGHTNESS_HOLD_CYCLES <= 1) ? 1 :
        $clog2(BRIGHTNESS_HOLD_CYCLES + 1);

    reg next_sync1;
    reg next_sync2;
    reg auto_sync1;
    reg auto_sync2;
    reg [DB_BITS-1:0] next_debounce_count;
    reg [DB_BITS-1:0] auto_debounce_count;
    reg [HOLD_BITS-1:0] hold_count;
    reg long_marked;
    reg [1:0] state;

    initial begin
        if (DEBOUNCE_CYCLES < 1 || BRIGHTNESS_HOLD_CYCLES < 1) begin
            $display("M6C_KEY_ROUTER_CONFIG_ERROR invalid timing parameter");
            $finish;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            next_sync1 <= 1'b1;
            next_sync2 <= 1'b1;
            auto_sync1 <= 1'b1;
            auto_sync2 <= 1'b1;
        end else begin
            next_sync1 <= key_next_n;
            next_sync2 <= next_sync1;
            auto_sync1 <= key_auto_n;
            auto_sync2 <= auto_sync1;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            next_stable_n <= 1'b1;
            auto_stable_n <= 1'b1;
            next_debounce_count <= 0;
            auto_debounce_count <= 0;
        end else begin
            if (next_sync2 == next_stable_n)
                next_debounce_count <= 0;
            else if (next_debounce_count == DEBOUNCE_CYCLES - 1) begin
                next_debounce_count <= 0;
                next_stable_n <= next_sync2;
            end else
                next_debounce_count <= next_debounce_count + 1'b1;

            if (auto_sync2 == auto_stable_n)
                auto_debounce_count <= 0;
            else if (auto_debounce_count == DEBOUNCE_CYCLES - 1) begin
                auto_debounce_count <= 0;
                auto_stable_n <= auto_sync2;
            end else
                auto_debounce_count <= auto_debounce_count + 1'b1;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ST_IDLE;
            hold_count <= 0;
            long_marked <= 1'b0;
            next_event <= 1'b0;
            auto_event <= 1'b0;
            brightness_event <= 1'b0;
        end else begin
            next_event <= 1'b0;
            auto_event <= 1'b0;
            brightness_event <= 1'b0;
            case (state)
                ST_IDLE: begin
                    hold_count <= 0;
                    long_marked <= 1'b0;
                    if (!next_stable_n && !auto_stable_n)
                        state <= ST_CHORD;
                    else if (!next_stable_n)
                        state <= ST_NEXT;
                    else if (!auto_stable_n)
                        state <= ST_AUTO;
                end

                ST_NEXT: begin
                    if (!next_stable_n && !auto_stable_n)
                        state <= ST_CHORD;
                    else if (next_stable_n) begin
                        next_event <= 1'b1;
                        state <= ST_IDLE;
                    end
                end

                ST_AUTO: begin
                    if (!next_stable_n && !auto_stable_n) begin
                        hold_count <= 0;
                        long_marked <= 1'b0;
                        state <= ST_CHORD;
                    end else if (auto_stable_n) begin
                        if (long_marked)
                            brightness_event <= 1'b1;
                        else
                            auto_event <= 1'b1;
                        hold_count <= 0;
                        long_marked <= 1'b0;
                        state <= ST_IDLE;
                    end else if (!long_marked) begin
                        if (hold_count == BRIGHTNESS_HOLD_CYCLES - 1)
                            long_marked <= 1'b1;
                        else
                            hold_count <= hold_count + 1'b1;
                    end
                end

                ST_CHORD: begin
                    hold_count <= 0;
                    long_marked <= 1'b0;
                    if (next_stable_n && auto_stable_n)
                        state <= ST_IDLE;
                end

                default: state <= ST_IDLE;
            endcase
        end
    end
endmodule
