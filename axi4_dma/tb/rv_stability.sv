`default_nettype none
// Observe edge-sampled payloads; reset/flush cancellation is supplied as rst_n.
module rv_stability #(
    parameter int unsigned WIDTH = 1
) (
    input logic clk,
    input logic rst_n,
    input logic valid,
    input logic ready,
    input logic [WIDTH-1:0] payload
);
    timeunit 1ns / 1ps;

    logic stalled = 0;
    logic [WIDTH-1:0] held;

    always @(posedge clk) begin
        if (!rst_n) begin
            stalled <= 1'b0;
        end else begin
            if ((valid !== 1'b0 && valid !== 1'b1) || (ready !== 1'b0 && ready !== 1'b1)) begin
                $fatal(1, "RV: %m unknown handshake control");
            end
            if (valid && $isunknown(payload)) begin
                $fatal(1, "RV: %m unknown payload while valid");
            end
            if (stalled && (valid !== 1'b1 || payload !== held)) begin
                $fatal(1, "RV: %m changed valid/payload under backpressure");
            end
            stalled <= valid && !ready;
            held <= payload;
        end
    end

endmodule
`default_nettype wire
