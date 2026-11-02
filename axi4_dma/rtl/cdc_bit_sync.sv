`default_nettype none
// For independent levels or Gray pointers only. Records cross through dma_async_fifo.
module cdc_bit_sync #(
    parameter int unsigned WIDTH = 1,
    parameter int unsigned STAGES = 2,
    localparam int unsigned DATA_BITS = WIDTH == 0 ? 1 : WIDTH,
    localparam int unsigned STAGE_COUNT = STAGES < 2 ? 2 : STAGES
) (
    input logic clk,
    input logic rst_n,
    input logic [DATA_BITS-1:0] async_data,
    output logic [DATA_BITS-1:0] sync_data
);
    timeunit 1ns / 1ps;
    (* ASYNC_REG = "TRUE" *) logic [DATA_BITS-1:0] sync_pipe[STAGE_COUNT];
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int stage = 0; stage < STAGE_COUNT; stage = stage + 1) begin
                sync_pipe[stage] <= '0;
            end
        end else begin
            sync_pipe[0] <= async_data;
            for (int stage = 1; stage < STAGE_COUNT; stage = stage + 1) begin
                sync_pipe[stage] <= sync_pipe[stage-1];
            end
        end
    end
    assign sync_data = sync_pipe[STAGE_COUNT-1];
`ifndef SYNTHESIS
    initial begin
        if (WIDTH == 0 || STAGES < 2) begin
            $fatal(1, "PARAM: synchronizer needs positive width and at least two stages");
        end
    end
`endif
endmodule
`default_nettype wire
