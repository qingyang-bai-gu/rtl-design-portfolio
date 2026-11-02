`default_nettype none
`include "dma_checks.svh"
// One planned full-width burst. The source holds stalled data; source pop equals W acceptance.
module dma_write_engine #(
    parameter int unsigned ADDR_WIDTH = 32,
    parameter int unsigned DATA_WIDTH = 128,
    parameter int unsigned MAX_BURST_BEATS = 16,
    parameter int unsigned ID_WIDTH = 1,
    localparam int unsigned DATA_BITS = DATA_WIDTH == 0 ? 1 : DATA_WIDTH,
    localparam int unsigned ID_BITS = ID_WIDTH == 0 ? 1 : ID_WIDTH,
    localparam int unsigned STROBE_BITS = DATA_WIDTH < 8 ? 1 : DATA_WIDTH / 8
) (
    input logic clk,
    input logic rst_n,
    input logic req_valid,
    output logic req_ready,
    input logic [ADDR_WIDTH-1:0] req_addr,
    input logic [8:0] req_beats,
    input logic [ID_BITS-1:0] req_id,
    output logic [ID_BITS-1:0] awid,
    output logic [ADDR_WIDTH-1:0] awaddr,
    output logic [7:0] awlen,
    output logic [2:0] awsize,
    output logic [1:0] awburst,
    output logic awvalid,
    input logic awready,
    input logic [DATA_BITS-1:0] data,
    input logic data_valid,
    output logic data_ready,
    output logic [DATA_BITS-1:0] wdata,
    output logic [STROBE_BITS-1:0] wstrb,
    output logic wlast,
    output logic wvalid,
    input logic wready,
    input logic [ID_BITS-1:0] bid,
    input logic [1:0] bresp,
    input logic bvalid,
    output logic bready,
    output logic result_valid,
    input logic result_ready,
    output logic result_error
);
    timeunit 1ns / 1ps;

    typedef enum logic [2:0] {
        IDLE,
        ADDRESS,
        DATA,
        RESPONSE,
        RESULT
    } state_t;
    state_t state;
    logic [ADDR_WIDTH-1:0] burst_addr;
    logic [ID_BITS-1:0] burst_id;
    logic [8:0] burst_beats;
    logic [8:0] beats_remaining;
    assign req_ready = rst_n && state == IDLE;
    assign awvalid = rst_n && state == ADDRESS;
    assign awaddr = burst_addr;
    assign awid = burst_id;
    assign awlen = 8'(burst_beats - 9'd1);
    assign awsize = 3'($clog2(DATA_WIDTH / 8));
    assign awburst = 2'b01;
    assign wdata = data;
    assign wstrb = '1;
    assign wlast = beats_remaining == 1;
    assign wvalid = rst_n && state == DATA && data_valid;
    // Source removal and AXI acceptance are the very same transfer.
    assign data_ready = rst_n && state == DATA && wready;
    assign bready = rst_n && state == RESPONSE;
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
                if (awvalid && awready) begin
                    state <= DATA;
                end
                DATA:
                if (wvalid && wready) begin
                    beats_remaining <= beats_remaining - 9'd1;
                    if (beats_remaining == 1) begin
                        state <= RESPONSE;
                    end
                end
                RESPONSE:
                if (bvalid && bready) begin
                    result_error <= bid != burst_id || bresp != 2'b00;
                    state <= RESULT;
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
