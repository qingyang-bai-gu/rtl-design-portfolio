`default_nettype none
`include "dma_checks.svh"
// Sequential store-and-forward DMA. Reset must also cancel the attached slave channels.
module axi_dma #(
    parameter int unsigned ADDR_WIDTH = 32,
    parameter int unsigned DATA_WIDTH = 128,
    parameter int unsigned MAX_BURST_BEATS = 16,
    parameter int unsigned BUFFER_DEPTH = MAX_BURST_BEATS,
    parameter int unsigned TAG_WIDTH = 8,
    parameter int unsigned ID_WIDTH = 1,
    localparam int unsigned DATA_BITS = DATA_WIDTH == 0 ? 1 : DATA_WIDTH,
    localparam int unsigned ID_BITS = ID_WIDTH == 0 ? 1 : ID_WIDTH,
    localparam int unsigned TAG_BITS = TAG_WIDTH == 0 ? 1 : TAG_WIDTH,
    localparam int unsigned STROBE_BITS = DATA_WIDTH < 8 ? 1 : DATA_WIDTH / 8
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
    output logic [ID_BITS-1:0] arid,
    output logic [ADDR_WIDTH-1:0] araddr,
    output logic [7:0] arlen,
    output logic [2:0] arsize,
    output logic [1:0] arburst,
    output logic arlock,
    output logic [3:0] arcache,
    output logic [3:0] arqos,
    output logic [3:0] arregion,
    output logic [2:0] arprot,
    output logic arvalid,
    input logic arready,
    input logic [ID_BITS-1:0] rid,
    input logic [DATA_BITS-1:0] rdata,
    input logic [1:0] rresp,
    input logic rlast,
    input logic rvalid,
    output logic rready,
    output logic [ID_BITS-1:0] awid,
    output logic [ADDR_WIDTH-1:0] awaddr,
    output logic [7:0] awlen,
    output logic [2:0] awsize,
    output logic [1:0] awburst,
    output logic awlock,
    output logic [3:0] awcache,
    output logic [3:0] awqos,
    output logic [3:0] awregion,
    output logic [2:0] awprot,
    output logic awvalid,
    input logic awready,
    output logic [DATA_BITS-1:0] wdata,
    output logic [STROBE_BITS-1:0] wstrb,
    output logic wlast,
    output logic wvalid,
    input logic wready,
    input logic [ID_BITS-1:0] bid,
    input logic [1:0] bresp,
    input logic bvalid,
    output logic bready
);
    timeunit 1ns / 1ps;

    logic [ADDR_WIDTH-1:0] plan_src;
    logic [ADDR_WIDTH-1:0] plan_dst;
    logic [ADDR_WIDTH-1:0] read_req_addr;
    logic [ADDR_WIDTH-1:0] write_req_addr;
    logic [ADDR_WIDTH:0] plan_remaining;
    logic plan_valid;
    logic [8:0] plan_beats;
    logic [8:0] read_req_beats;
    logic [8:0] write_req_beats;
    logic [12:0] plan_bytes;
    logic buffer_empty;
    logic buffer_flush;
    logic read_req_valid;
    logic read_req_ready;
    logic read_result_valid;
    logic read_result_ready;
    logic write_req_valid;
    logic write_req_ready;
    logic write_result_valid;
    logic write_result_ready;
    logic read_result_error;
    logic write_result_error;
    logic [DATA_BITS-1:0] read_data;
    logic [DATA_BITS-1:0] write_data;
    logic read_data_valid;
    logic read_data_ready;
    logic write_data_valid;
    logic write_data_ready;
    assign arlock = 0;
    assign arcache = 0;
    assign arprot = 0;
    assign arqos = 0;
    assign arregion = 0;
    assign awlock = 0;
    assign awcache = 0;
    assign awprot = 0;
    assign awqos = 0;
    assign awregion = 0;
    dma_burst_planner #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .MAX_BURST_BEATS(MAX_BURST_BEATS)
    ) planner (
        .src_addr(plan_src),
        .dst_addr(plan_dst),
        .remaining_bytes(plan_remaining),
        .plan_valid(plan_valid),
        .plan_beats(plan_beats),
        .plan_bytes(plan_bytes)
    );
    dma_controller #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .MAX_BURST_BEATS(MAX_BURST_BEATS),
        .TAG_WIDTH(TAG_WIDTH)
    ) controller (
        .clk(clk),
        .rst_n(rst_n),
        .desc_valid(desc_valid),
        .desc_ready(desc_ready),
        .desc_src(desc_src),
        .desc_dst(desc_dst),
        .desc_length(desc_length),
        .desc_tag(desc_tag),
        .completion_valid(completion_valid),
        .completion_ready(completion_ready),
        .completion_tag(completion_tag),
        .completion_status(completion_status),
        .plan_src(plan_src),
        .plan_dst(plan_dst),
        .plan_remaining(plan_remaining),
        .plan_valid(plan_valid),
        .plan_beats(plan_beats),
        .plan_bytes(plan_bytes),
        .buffer_empty(buffer_empty),
        .buffer_flush(buffer_flush),
        .read_req_valid(read_req_valid),
        .read_req_ready(read_req_ready),
        .read_req_addr(read_req_addr),
        .read_req_beats(read_req_beats),
        .read_result_valid(read_result_valid),
        .read_result_ready(read_result_ready),
        .read_result_error(read_result_error),
        .write_req_valid(write_req_valid),
        .write_req_ready(write_req_ready),
        .write_req_addr(write_req_addr),
        .write_req_beats(write_req_beats),
        .write_result_valid(write_result_valid),
        .write_result_ready(write_result_ready),
        .write_result_error(write_result_error)
    );
    dma_read_engine #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .MAX_BURST_BEATS(MAX_BURST_BEATS),
        .ID_WIDTH(ID_WIDTH)
    ) reader (
        .clk(clk),
        .rst_n(rst_n),
        .req_valid(read_req_valid),
        .req_ready(read_req_ready),
        .req_addr(read_req_addr),
        .req_beats(read_req_beats),
        .req_id('0),
        .arid(arid),
        .araddr(araddr),
        .arlen(arlen),
        .arsize(arsize),
        .arburst(arburst),
        .arvalid(arvalid),
        .arready(arready),
        .rid(rid),
        .rdata(rdata),
        .rresp(rresp),
        .rlast(rlast),
        .rvalid(rvalid),
        .rready(rready),
        .data(read_data),
        .data_valid(read_data_valid),
        .data_ready(read_data_ready),
        .result_valid(read_result_valid),
        .result_ready(read_result_ready),
        .result_error(read_result_error)
    );
    dma_burst_buffer #(
        .DATA_WIDTH(DATA_WIDTH),
        .DEPTH(BUFFER_DEPTH)
    ) buffer (
        .clk(clk),
        .rst_n(rst_n),
        .flush(buffer_flush),
        .push_data(read_data),
        .push_valid(read_data_valid),
        .push_ready(read_data_ready),
        .pop_data(write_data),
        .pop_valid(write_data_valid),
        .pop_ready(write_data_ready),
        .occupancy(),
        .empty(buffer_empty),
        .full()
    );
    dma_write_engine #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .MAX_BURST_BEATS(MAX_BURST_BEATS),
        .ID_WIDTH(ID_WIDTH)
    ) writer (
        .clk(clk),
        .rst_n(rst_n),
        .req_valid(write_req_valid),
        .req_ready(write_req_ready),
        .req_addr(write_req_addr),
        .req_beats(write_req_beats),
        .req_id('0),
        .awid(awid),
        .awaddr(awaddr),
        .awlen(awlen),
        .awsize(awsize),
        .awburst(awburst),
        .awvalid(awvalid),
        .awready(awready),
        .data(write_data),
        .data_valid(write_data_valid),
        .data_ready(write_data_ready),
        .wdata(wdata),
        .wstrb(wstrb),
        .wlast(wlast),
        .wvalid(wvalid),
        .wready(wready),
        .bid(bid),
        .bresp(bresp),
        .bvalid(bvalid),
        .bready(bready),
        .result_valid(write_result_valid),
        .result_ready(write_result_ready),
        .result_error(write_result_error)
    );
`ifndef SYNTHESIS
    initial begin
        `DMA_CHECK_GEOMETRY
        if (BUFFER_DEPTH < MAX_BURST_BEATS || BUFFER_DEPTH == 0) begin
            $fatal(1, "PARAM: buffer must hold a complete maximum burst");
        end
        if (ID_WIDTH == 0 || TAG_WIDTH == 0) begin
            $fatal(1, "PARAM: ID/tag width positive");
        end
    end
`endif

endmodule
`default_nettype wire
