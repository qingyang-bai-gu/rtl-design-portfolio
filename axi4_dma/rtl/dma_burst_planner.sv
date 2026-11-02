`default_nettype none
`include "dma_checks.svh"
// Stateless paired-burst policy: remaining bytes, project limit, and both page limits.
module dma_burst_planner #(
    parameter int unsigned ADDR_WIDTH = 32,
    parameter int unsigned DATA_WIDTH = 128,
    parameter int unsigned MAX_BURST_BEATS = 16
) (
    input logic [ADDR_WIDTH-1:0] src_addr,
    input logic [ADDR_WIDTH-1:0] dst_addr,
    input logic [ADDR_WIDTH:0] remaining_bytes,
    output logic plan_valid,
    output logic [8:0] plan_beats,
    output logic [12:0] plan_bytes
);
    timeunit 1ns / 1ps;

    localparam int unsigned BEAT_BYTES = DATA_WIDTH / 8;
    localparam int unsigned SIZE = $clog2(BEAT_BYTES);
    logic [ADDR_WIDTH:0] count;
    logic [12:0] src_page_beats;
    logic [12:0] dst_page_beats;
    logic [ADDR_WIDTH+1:0] src_end;
    logic [ADDR_WIDTH+1:0] dst_end;
    logic [ADDR_WIDTH+1:0] limit;

    always_comb begin
        plan_valid = 1'b0;
        plan_beats = 0;
        plan_bytes = 0;
        count = remaining_bytes >> SIZE;
        src_page_beats = (13'd4096 - {1'b0, 12'(src_addr)}) >> SIZE;
        dst_page_beats = (13'd4096 - {1'b0, 12'(dst_addr)}) >> SIZE;
        src_end = {2'b0, src_addr} + {1'b0, remaining_bytes};
        dst_end = {2'b0, dst_addr} + {1'b0, remaining_bytes};
        limit = {{(ADDR_WIDTH + 1) {1'b0}}, 1'b1} << ADDR_WIDTH;
        if (count > (ADDR_WIDTH + 1)'(MAX_BURST_BEATS)) begin
            count = (ADDR_WIDTH + 1)'(MAX_BURST_BEATS);
        end
        if (count > (ADDR_WIDTH + 1)'(src_page_beats)) begin
            count = (ADDR_WIDTH + 1)'(src_page_beats);
        end
        if (count > (ADDR_WIDTH + 1)'(dst_page_beats)) begin
            count = (ADDR_WIDTH + 1)'(dst_page_beats);
        end
        if (remaining_bytes != 0 && src_addr % ADDR_WIDTH'(BEAT_BYTES) == 0 &&
            dst_addr % ADDR_WIDTH'(BEAT_BYTES) == 0 &&
            remaining_bytes % (ADDR_WIDTH+1)'(BEAT_BYTES) == 0 &&
            src_end <= limit && dst_end <= limit) begin
            plan_valid = 1'b1;
            plan_beats = 9'(count);
            plan_bytes = 13'(count << SIZE);
        end
    end
`ifndef SYNTHESIS
    initial begin
        `DMA_CHECK_GEOMETRY
    end
`endif

endmodule
`default_nettype wire
