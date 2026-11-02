`default_nettype none
`include "dma_checks.svh"
// One descriptor at a time; register each plan, resolve read success, then request its write.
module dma_controller #(
    parameter int unsigned ADDR_WIDTH = 32,
    parameter int unsigned DATA_WIDTH = 128,
    parameter int unsigned MAX_BURST_BEATS = 16,
    parameter int unsigned TAG_WIDTH = 8,
    localparam int unsigned TAG_BITS = TAG_WIDTH == 0 ? 1 : TAG_WIDTH
) (
    input logic clk,
    input logic rst_n,
    input logic desc_valid,
    output logic desc_ready,
    input logic [ADDR_WIDTH-1:0] desc_src,
    input logic [ADDR_WIDTH-1:0] desc_dst,
    input logic [ADDR_WIDTH:0] desc_length,
    input logic [TAG_BITS-1:0] desc_tag,
    output logic completion_valid,
    input logic completion_ready,
    output logic [TAG_BITS-1:0] completion_tag,
    output logic [1:0] completion_status,
    output logic [ADDR_WIDTH-1:0] plan_src,
    output logic [ADDR_WIDTH-1:0] plan_dst,
    output logic [ADDR_WIDTH:0] plan_remaining,
    input logic plan_valid,
    input logic [8:0] plan_beats,
    input logic [12:0] plan_bytes,
    input logic buffer_empty,
    output logic buffer_flush,
    output logic read_req_valid,
    input logic read_req_ready,
    output logic [ADDR_WIDTH-1:0] read_req_addr,
    output logic [8:0] read_req_beats,
    input logic read_result_valid,
    output logic read_result_ready,
    input logic read_result_error,
    output logic write_req_valid,
    input logic write_req_ready,
    output logic [ADDR_WIDTH-1:0] write_req_addr,
    output logic [8:0] write_req_beats,
    input logic write_result_valid,
    output logic write_result_ready,
    input logic write_result_error
);
    timeunit 1ns / 1ps;

    localparam int unsigned BEAT_BYTES = DATA_WIDTH / 8;
    localparam logic [1:0] OK = 0;
    localparam logic [1:0] DESC_ERROR = 1;
    localparam logic [1:0] READ_ERROR = 2;
    localparam logic [1:0] WRITE_ERROR = 3;
    typedef enum logic [3:0] {
        IDLE,
        PLAN,
        READ_REQ,
        READ_WAIT,
        WRITE_REQ,
        WRITE_WAIT,
        FLUSH,
        COMPLETE
    } state_t;
    state_t state;
    logic [ADDR_WIDTH-1:0] src;
    logic [ADDR_WIDTH-1:0] dst;
    logic [ADDR_WIDTH:0] remaining;
    logic [8:0] chunk_beats;
    logic [12:0] chunk_bytes;

    function automatic logic legal_descriptor(input logic [ADDR_WIDTH-1:0] source_addr,
                                              input logic [ADDR_WIDTH-1:0] destination_addr,
                                              input logic [ADDR_WIDTH:0] length_bytes);
        logic [ADDR_WIDTH+1:0] source_end;
        logic [ADDR_WIDTH+1:0] destination_end;
        logic [ADDR_WIDTH+1:0] address_limit;
        begin
            source_end = {2'b0, source_addr} + {1'b0, length_bytes};
            destination_end = {2'b0, destination_addr} + {1'b0, length_bytes};
            address_limit = {{(ADDR_WIDTH + 1) {1'b0}}, 1'b1} << ADDR_WIDTH;
            legal_descriptor = length_bytes != 0 && source_addr % ADDR_WIDTH'(BEAT_BYTES) == 0 &&
                destination_addr % ADDR_WIDTH'(BEAT_BYTES) == 0 &&
                length_bytes % (ADDR_WIDTH+1)'(BEAT_BYTES) == 0 &&
                source_end <= address_limit && destination_end <= address_limit &&
                (source_end <= {2'b0, destination_addr} || destination_end <= {2'b0, source_addr});
        end
    endfunction
    assign desc_ready = rst_n && state == IDLE;
    assign completion_valid = rst_n && state == COMPLETE;
    assign plan_src = src;
    assign plan_dst = dst;
    assign plan_remaining = remaining;
    assign read_req_valid = rst_n && state == READ_REQ;
    assign read_req_addr = src;
    assign read_req_beats = chunk_beats;
    assign read_result_ready = rst_n && state == READ_WAIT;
    assign write_req_valid = rst_n && state == WRITE_REQ;
    assign write_req_addr = dst;
    assign write_req_beats = chunk_beats;
    assign write_result_ready = rst_n && state == WRITE_WAIT;
    assign buffer_flush = rst_n && state == FLUSH;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            state <= IDLE;
            src <= '0;
            dst <= '0;
            remaining <= '0;
            chunk_beats <= '0;
            chunk_bytes <= '0;
            completion_tag <= '0;
            completion_status <= OK;
        end else begin
            case (state)
                IDLE:
                if (desc_valid && desc_ready) begin
                    src <= desc_src;
                    dst <= desc_dst;
                    remaining <= desc_length;
                    completion_tag <= desc_tag;
                    if (legal_descriptor(desc_src, desc_dst, desc_length)) begin
                        completion_status <= OK;
                        state <= PLAN;
                    end else begin
                        completion_status <= DESC_ERROR;
                        state <= COMPLETE;
                    end
                end
                PLAN:
                if (buffer_empty) begin
                    if (plan_valid) begin
                        chunk_beats <= plan_beats;
                        chunk_bytes <= plan_bytes;
                        state <= READ_REQ;
                    end else begin
                        completion_status <= DESC_ERROR;
                        state <= COMPLETE;
                    end
                end
                READ_REQ:
                if (read_req_valid && read_req_ready) begin
                    state <= READ_WAIT;
                end
                READ_WAIT:
                if (read_result_valid && read_result_ready) begin
                    if (read_result_error) begin
                        completion_status <= READ_ERROR;
                        state <= FLUSH;
                    end else begin
                        state <= WRITE_REQ;
                    end
                end
                WRITE_REQ:
                if (write_req_valid && write_req_ready) begin
                    state <= WRITE_WAIT;
                end
                WRITE_WAIT:
                if (write_result_valid && write_result_ready) begin
                    if (write_result_error) begin
                        completion_status <= WRITE_ERROR;
                        state <= COMPLETE;
                    end else begin
                        src <= src + ADDR_WIDTH'(chunk_bytes);
                        dst <= dst + ADDR_WIDTH'(chunk_bytes);
                        remaining <= remaining - (ADDR_WIDTH + 1)'(chunk_bytes);
                        if (remaining == (ADDR_WIDTH + 1)'(chunk_bytes)) begin
                            state <= COMPLETE;
                        end else begin
                            state <= PLAN;
                        end
                    end
                end
                FLUSH: state <= COMPLETE;
                COMPLETE:
                if (completion_valid && completion_ready) begin
                    state <= IDLE;
                end
                default: state <= IDLE;
            endcase
        end
    end
`ifndef SYNTHESIS
    initial begin
        `DMA_CHECK_GEOMETRY
        if (TAG_WIDTH == 0) begin
            $fatal(1, "PARAM: TAG_WIDTH must be positive");
        end
    end
`endif

endmodule
`default_nettype wire
