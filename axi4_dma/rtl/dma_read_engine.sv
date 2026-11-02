`default_nettype none
`include "dma_checks.svh"
// One aligned, page-legal request at a time. Drain the expected count even after an R error.
module dma_read_engine #(
    parameter int unsigned ADDR_WIDTH = 32,
    parameter int unsigned DATA_WIDTH = 128,
    parameter int unsigned MAX_BURST_BEATS = 16,
    parameter int unsigned ID_WIDTH = 1,
    localparam int unsigned DATA_BITS = DATA_WIDTH == 0 ? 1 : DATA_WIDTH,
    localparam int unsigned ID_BITS = ID_WIDTH == 0 ? 1 : ID_WIDTH
) (
    input logic clk,
    input logic rst_n,
    input logic req_valid,
    output logic req_ready,
    input logic [ADDR_WIDTH-1:0] req_addr,
    input logic [8:0] req_beats,
    input logic [ID_BITS-1:0] req_id,
    output logic [ID_BITS-1:0] arid,
    output logic [ADDR_WIDTH-1:0] araddr,
    output logic [7:0] arlen,
    output logic [2:0] arsize,
    output logic [1:0] arburst,
    output logic arvalid,
    input logic arready,
    input logic [ID_BITS-1:0] rid,
    input logic [DATA_BITS-1:0] rdata,
    input logic [1:0] rresp,
    input logic rlast,
    input logic rvalid,
    output logic rready,
    output logic [DATA_BITS-1:0] data,
    output logic data_valid,
    input logic data_ready,
    output logic result_valid,
    input logic result_ready,
    output logic result_error
);
    timeunit 1ns / 1ps;

    typedef enum logic [1:0] {
        IDLE,
        ADDRESS,
        DATA,
        RESULT
    } state_t;
    state_t state;
    logic [ADDR_WIDTH-1:0] burst_addr;
    logic [ID_BITS-1:0] burst_id;
    logic [8:0] burst_beats;
    logic [8:0] beats_remaining;
    assign req_ready = rst_n && state == IDLE;
    assign arvalid = rst_n && state == ADDRESS;
    assign araddr = burst_addr;
    assign arid = burst_id;
    assign arlen = 8'(burst_beats - 9'd1);
    assign arsize = 3'($clog2(DATA_WIDTH / 8));
    assign arburst = 2'b01;
    assign data = rdata;
    assign data_valid = rst_n && state == DATA && rvalid;
    assign rready = rst_n && state == DATA && data_ready;
    assign result_valid = rst_n && state == RESULT;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            state <= IDLE;
            burst_addr <= '0;
            burst_id <= '0;
            burst_beats <= '0;
            beats_remaining <= '0;
            result_error <= 1'b0;
        end else begin
            case (state)
                IDLE:
                if (req_valid && req_ready) begin
                    burst_addr <= req_addr;
                    burst_id <= req_id;
                    burst_beats <= req_beats;
                    beats_remaining <= req_beats;
                    result_error <= req_beats == 0 || req_beats > 9'(MAX_BURST_BEATS);
                    if (req_beats == 0 || req_beats > 9'(MAX_BURST_BEATS)) begin
                        state <= RESULT;
                    end else begin
                        state <= ADDRESS;
                    end
                end
                ADDRESS:
                if (arvalid && arready) begin
                    state <= DATA;
                end
                DATA:
                if (rvalid && rready) begin
                    if (rid != burst_id || rresp != 2'b00 || rlast != (beats_remaining == 1)) begin
                        result_error <= 1'b1;
                    end
                    beats_remaining <= beats_remaining - 9'd1;
                    if (beats_remaining == 1) begin
                        state <= RESULT;
                    end
                end
                RESULT:
                if (result_valid && result_ready) begin
                    state <= IDLE;
                end
                default: state <= IDLE;
            endcase
        end
    end
`ifndef SYNTHESIS
    initial begin
        `DMA_CHECK_GEOMETRY
        if (ID_WIDTH == 0) begin
            $fatal(1, "PARAM: ID_WIDTH must be positive");
        end
    end
`endif

endmodule
`default_nettype wire
