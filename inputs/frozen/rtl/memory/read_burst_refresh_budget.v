`include "global_def.v"



// Admission only: the official source must complete every admitted burst.

// Reserve a burst for delayed refresh indication, a burst for the next transfer,

// and 64 clocks for admission/return/drain. See WhiteLineBoundaryAudit.md for

// encrypted-controller evidence and the limits of the external timing model.

module read_burst_refresh_budget #(

    parameter integer BURST_WORDS = 256,

    parameter integer REFRESH_INTERVAL = `SELF_REFRESH_INTERVAL

) (

    input wire mem_clk,

    input wire rst,

    input wire initialized,

    input wire refresh_active,

    input wire controller_busy,

    output wire permit

);

    localparam integer AGE_WIDTH = (REFRESH_INTERVAL < 2) ? 1 :

                                  $clog2(REFRESH_INTERVAL + 1);

    localparam integer WINDOW_END = REFRESH_INTERVAL - BURST_WORDS - BURST_WORDS - 64;

    localparam [AGE_WIDTH-1:0] AGE_LIMIT = REFRESH_INTERVAL;

    reg refresh_q;

    reg phase_known;

    reg [AGE_WIDTH-1:0] phase_age;



    always @(posedge mem_clk or posedge rst) begin

        if (rst) begin

            refresh_q <= 1'b0;

            phase_known <= 1'b0;

            phase_age <= {AGE_WIDTH{1'b0}};

        end else if (!initialized) begin

            // Do not mistake a still-high initialization indication for a new

            // periodic refresh when initialized rises.

            refresh_q <= refresh_active;

            phase_known <= 1'b0;

            phase_age <= {AGE_WIDTH{1'b0}};

        end else begin

            refresh_q <= refresh_active;

            if (refresh_active && !refresh_q) begin

                phase_known <= 1'b1;

                phase_age <= {AGE_WIDTH{1'b0}};

            end else if (phase_age < AGE_LIMIT) begin

                phase_age <= phase_age + 1'b1;

            end

        end

    end



    // Unknown/expired phase fails closed, including a missing refresh event.

    assign permit = !rst && initialized && phase_known && (WINDOW_END > 0) &&

                    (phase_age < WINDOW_END) && !controller_busy && !refresh_active;

endmodule

