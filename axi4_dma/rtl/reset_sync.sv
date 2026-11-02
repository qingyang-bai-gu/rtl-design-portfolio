`default_nettype none
// Common asynchronous assertion; each clock domain releases after STAGES local edges.
module reset_sync #(
    parameter int unsigned STAGES = 2,
    localparam int unsigned STAGE_COUNT = STAGES < 2 ? 2 : STAGES
) (
    input logic clk,
    input logic arst_n,
    output logic rst_n
);
    timeunit 1ns / 1ps;
    (* ASYNC_REG = "TRUE" *) logic [STAGE_COUNT-1:0] release_pipe;
    always_ff @(posedge clk or negedge arst_n) begin
        if (!arst_n) begin
            release_pipe <= '0;
        end else begin
            release_pipe <= {release_pipe[STAGE_COUNT-2:0], 1'b1};
        end
    end
    assign rst_n = arst_n && release_pipe[STAGE_COUNT-1];
`ifndef SYNTHESIS
    initial begin
        if (STAGES < 2) begin
            $fatal(1, "PARAM: reset synchronizer needs at least two stages");
        end
    end
`endif
endmodule
`default_nettype wire
