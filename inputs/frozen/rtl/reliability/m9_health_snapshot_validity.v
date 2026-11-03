// A FIFO level is displayable only after a fresh commit in its active epoch.
// Dropping expected clears stale validity before a later epoch can reuse it.
module m9_health_snapshot_validity (
    input wire clk,input wire rst,
    input wire [2:0] expected,input wire [2:0] commit,
    output reg [2:0] valid
);
    always @(posedge clk) begin
        if(rst) valid<=3'b000;
        else valid<=(valid | commit) & expected;
    end
endmodule
