`default_nettype none
// Elaboration smoke check only; not an arbiter behavioral or fairness testbench.
module tb_arbiter_elaboration;
    timeunit 1ns / 1ps;

    parameter int unsigned REQUESTERS = 4;
    round_robin_arbiter #(
        .REQUESTERS(REQUESTERS)
    ) dut (
        .clk(1'b0),
        .rst_n(1'b0),
        .request('0),
        .grant_ready(1'b0),
        .grant_valid(),
        .grant_onehot(),
        .grant_index()
    );

    initial begin
        #1;
        $display("PASS arbiter elaboration REQUESTERS=%0d", REQUESTERS);
        $finish;
    end

endmodule
`default_nettype wire
