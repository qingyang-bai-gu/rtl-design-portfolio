`default_nettype none
// Hold a selected owner under stall; advance priority only on an accepted grant.
// Requesters must retain an offered request until its grant is accepted or reset.
module round_robin_arbiter #(
    parameter int unsigned REQUESTERS = 4,
    parameter int unsigned INDEX_WIDTH = REQUESTERS <= 1 ? 1 : $clog2(REQUESTERS),
    localparam int unsigned REQUEST_BITS = REQUESTERS == 0 ? 1 : REQUESTERS,
    localparam int unsigned INDEX_BITS = INDEX_WIDTH == 0 ? 1 : INDEX_WIDTH
) (
    input logic clk,
    input logic rst_n,
    input logic [REQUEST_BITS-1:0] request,
    output logic grant_valid,
    output logic [REQUEST_BITS-1:0] grant_onehot,
    output logic [INDEX_BITS-1:0] grant_index,
    input logic grant_ready
);
    timeunit 1ns / 1ps;
    logic [INDEX_BITS-1:0] next_priority;
    logic [INDEX_BITS-1:0] held_index;
    logic held;
    logic found;
    int unsigned scan_index;

    always_comb begin
        grant_valid = 1'b0;
        grant_onehot = '0;
        grant_index = '0;
        found = 1'b0;
        scan_index = int'(next_priority);
        if (rst_n) begin
            if (held) begin
                grant_valid = 1'b1;
                grant_index = held_index;
                grant_onehot[held_index] = 1'b1;
            end else begin
                for (int unsigned offset = 0; offset < REQUESTERS; offset = offset + 1) begin
                    if (!found && request[scan_index]) begin
                        found = 1'b1;
                        grant_valid = 1'b1;
                        grant_index = INDEX_BITS'(scan_index);
                        grant_onehot[scan_index] = 1'b1;
                    end
                    if (scan_index == REQUESTERS - 1) begin
                        scan_index = 0;
                    end else begin
                        scan_index = scan_index + 1;
                    end
                end
            end
        end
    end

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            next_priority <= '0;
            held_index <= '0;
            held <= 1'b0;
        end else if (grant_valid && grant_ready) begin
            held <= 1'b0;
            if (grant_index == INDEX_BITS'(REQUESTERS - 1)) begin
                next_priority <= '0;
            end else begin
                next_priority <= grant_index + 1'b1;
            end
        end else if (grant_valid && !held) begin
            held <= 1'b1;
            held_index <= grant_index;
        end
    end
`ifndef SYNTHESIS
    initial begin
        if (REQUESTERS == 0) begin
            $fatal(1, "PARAM: REQUESTERS must be positive");
        end
        if (INDEX_WIDTH == 0 || INDEX_WIDTH < $clog2(REQUESTERS)) begin
            $fatal(1, "PARAM: arbiter index width too small");
        end
    end
    always @(posedge clk) begin
        if (rst_n && held && !request[held_index]) begin
            $fatal(1, "CONTRACT: arbiter requester withdrew a stalled offer");
        end
    end
`endif
endmodule
`default_nettype wire
