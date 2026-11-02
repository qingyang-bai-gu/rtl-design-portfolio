`timescale 1ns/1ps
`default_nettype none

module fir_coeff_rom #(
    parameter COEFF_FILE = "coefficients/lowpass_q15.hex"
) (
    input  wire               clk,
    input  wire               rd_en,
    input  wire [5:0]         rd_addr,
    output reg signed [15:0]  rd_data
);
    reg signed [15:0] mem [0:63];
    initial $readmemh(COEFF_FILE, mem);
    always @(posedge clk) begin
        if (rd_en) rd_data <= mem[rd_addr];
    end
endmodule

`default_nettype wire
