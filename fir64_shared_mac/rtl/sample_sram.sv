`timescale 1ns/1ps
`default_nettype none

// 64 x 16 single-clock, synchronous-read 1R1W SRAM inference wrapper.
// No array reset: history_count in the controller masks unwritten locations.
// The controller never reads and writes the same address on the same edge.
module fir_sample_sram (
    input  wire               clk,
    input  wire               wr_en,
    input  wire [5:0]         wr_addr,
    input  wire signed [15:0] wr_data,
    input  wire               rd_en,
    input  wire [5:0]         rd_addr,
    output reg signed [15:0]  rd_data
);
    (* ram_style = "block" *) reg signed [15:0] mem [0:63];
    always @(posedge clk) begin
        if (wr_en) mem[wr_addr] <= wr_data;
        if (rd_en) rd_data <= mem[rd_addr];
    end
endmodule

`default_nettype wire
