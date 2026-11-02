`timescale 1ns/1ps
`default_nettype none

// Common asynchronous assertion, two destination-clock edges to release.
module fir_reset_sync (
    input  wire clk,
    input  wire arst_n,
    output wire rst_n
);
    (* ASYNC_REG = "TRUE" *) reg [1:0] release_ff;
    always @(posedge clk or negedge arst_n) begin
        if (!arst_n) release_ff <= 2'b00;
        else         release_ff <= {release_ff[0], 1'b1};
    end
    assign rst_n = release_ff[1];
endmodule

`default_nettype wire
