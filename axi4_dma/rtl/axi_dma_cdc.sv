`default_nettype none
// Descriptors and completions cross as complete records. The DMA/AXI datapath stays
// in axi_clk. Either reset request cancels BOTH domains, including queued work.
module axi_dma_cdc #(
    parameter int unsigned CDC_DEPTH = 4,
    parameter int unsigned CHANNELS = 4,
    parameter int unsigned ADDR_WIDTH = 32,
    parameter int unsigned DATA_WIDTH = 128,
    parameter int unsigned MAX_BURST_BEATS = 16,
    parameter int unsigned BUFFER_DEPTH = MAX_BURST_BEATS,
    parameter int unsigned TAG_WIDTH = 8,
    parameter int unsigned ID_WIDTH = 1,
    parameter int unsigned DESCRIPTOR_DEPTH = 2,
    parameter int unsigned COMPLETION_DEPTH = 1,
    parameter int unsigned COUNTER_WIDTH = 64,
    localparam int unsigned CHANNEL_COUNT = CHANNELS == 0 ? 1 : CHANNELS,
    localparam int unsigned DATA_BITS = DATA_WIDTH == 0 ? 1 : DATA_WIDTH,
    localparam int unsigned ID_BITS = ID_WIDTH == 0 ? 1 : ID_WIDTH,
    localparam int unsigned TAG_BITS = TAG_WIDTH == 0 ? 1 : TAG_WIDTH,
    localparam int unsigned STROBE_BITS = DATA_WIDTH < 8 ? 1 : DATA_WIDTH / 8,
    localparam int unsigned COUNTER_BITS = COUNTER_WIDTH == 0 ? 1 : COUNTER_WIDTH
) (
    input logic ctrl_clk,
    input logic axi_clk,
    input logic ctrl_arst_n,
    input logic axi_arst_n,
    output logic ctrl_domain_rst_n,
    output logic axi_domain_rst_n,
    input logic [CHANNEL_COUNT-1:0] desc_valid,
    output logic [CHANNEL_COUNT-1:0] desc_ready,
    input logic [CHANNEL_COUNT-1:0][ADDR_WIDTH-1:0] desc_src,
    input logic [CHANNEL_COUNT-1:0][ADDR_WIDTH-1:0] desc_dst,
    input logic [CHANNEL_COUNT-1:0][ADDR_WIDTH:0] desc_length,
    input logic [CHANNEL_COUNT-1:0][TAG_BITS-1:0] desc_tag,
    output logic [CHANNEL_COUNT-1:0] completion_valid,
    input logic [CHANNEL_COUNT-1:0] completion_ready,
    output logic [CHANNEL_COUNT-1:0][TAG_BITS-1:0] completion_tag,
    output logic [CHANNEL_COUNT-1:0][1:0] completion_status,
    output logic [COUNTER_BITS-1:0] cycle_count,
    output logic [COUNTER_BITS-1:0] active_cycle_count,
    output logic [COUNTER_BITS-1:0] descriptor_count,
    output logic [COUNTER_BITS-1:0] completion_count,
    output logic [COUNTER_BITS-1:0] error_count,
    output logic [COUNTER_BITS-1:0] read_burst_count,
    output logic [COUNTER_BITS-1:0] read_beat_count,
    output logic [COUNTER_BITS-1:0] write_burst_count,
    output logic [COUNTER_BITS-1:0] write_beat_count,
    output logic [COUNTER_BITS-1:0] write_response_count,
    output logic [COUNTER_BITS-1:0] ar_stall_count,
    output logic [COUNTER_BITS-1:0] r_stall_count,
    output logic [COUNTER_BITS-1:0] aw_stall_count,
    output logic [COUNTER_BITS-1:0] w_stall_count,
    output logic [COUNTER_BITS-1:0] b_stall_count,
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
    localparam int unsigned DESC_BITS = 3 * ADDR_WIDTH + 1 + TAG_BITS;
    localparam int unsigned COMP_BITS = TAG_BITS + 2;
    logic common_arst_n;
    logic [CHANNEL_COUNT-1:0] axi_desc_valid;
    logic [CHANNEL_COUNT-1:0] axi_desc_ready;
    logic [CHANNEL_COUNT-1:0][ADDR_WIDTH-1:0] axi_desc_src;
    logic [CHANNEL_COUNT-1:0][ADDR_WIDTH-1:0] axi_desc_dst;
    logic [CHANNEL_COUNT-1:0][ADDR_WIDTH:0] axi_desc_length;
    logic [CHANNEL_COUNT-1:0][TAG_BITS-1:0] axi_desc_tag;
    logic [CHANNEL_COUNT-1:0] axi_completion_valid;
    logic [CHANNEL_COUNT-1:0] axi_completion_ready;
    logic [CHANNEL_COUNT-1:0][TAG_BITS-1:0] axi_completion_tag;
    logic [CHANNEL_COUNT-1:0][1:0] axi_completion_status;
    assign common_arst_n = ctrl_arst_n && axi_arst_n;
    reset_sync control_reset (
        .clk(ctrl_clk),
        .arst_n(common_arst_n),
        .rst_n(ctrl_domain_rst_n)
    );
    reset_sync axi_reset (
        .clk(axi_clk),
        .arst_n(common_arst_n),
        .rst_n(axi_domain_rst_n)
    );
    for (genvar channel = 0; channel < CHANNELS; channel = channel + 1) begin : g_channel
        logic [DESC_BITS-1:0] descriptor_head;
        logic [COMP_BITS-1:0] completion_head;
        assign {axi_desc_src[channel], axi_desc_dst[channel],
                axi_desc_length[channel], axi_desc_tag[channel]} = descriptor_head;
        assign {completion_tag[channel], completion_status[channel]} = completion_head;
        dma_async_fifo #(
            .DATA_WIDTH(DESC_BITS),
            .DEPTH(CDC_DEPTH)
        ) descriptors (
            .wr_clk(ctrl_clk),
            .wr_rst_n(ctrl_domain_rst_n),
            .push_data({
                desc_src[channel], desc_dst[channel], desc_length[channel], desc_tag[channel]
            }),
            .push_valid(desc_valid[channel]),
            .push_ready(desc_ready[channel]),
            .rd_clk(axi_clk),
            .rd_rst_n(axi_domain_rst_n),
            .pop_data(descriptor_head),
            .pop_valid(axi_desc_valid[channel]),
            .pop_ready(axi_desc_ready[channel])
        );
        dma_async_fifo #(
            .DATA_WIDTH(COMP_BITS),
            .DEPTH(CDC_DEPTH)
        ) completions (
            .wr_clk(axi_clk),
            .wr_rst_n(axi_domain_rst_n),
            .push_data({axi_completion_tag[channel], axi_completion_status[channel]}),
            .push_valid(axi_completion_valid[channel]),
            .push_ready(axi_completion_ready[channel]),
            .rd_clk(ctrl_clk),
            .rd_rst_n(ctrl_domain_rst_n),
            .pop_data(completion_head),
            .pop_valid(completion_valid[channel]),
            .pop_ready(completion_ready[channel])
        );
    end
    axi_dma_multi #(
        .CHANNELS(CHANNELS),
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .MAX_BURST_BEATS(MAX_BURST_BEATS),
        .BUFFER_DEPTH(BUFFER_DEPTH),
        .TAG_WIDTH(TAG_WIDTH),
        .ID_WIDTH(ID_WIDTH),
        .DESCRIPTOR_DEPTH(DESCRIPTOR_DEPTH),
        .COMPLETION_DEPTH(COMPLETION_DEPTH),
        .COUNTER_WIDTH(COUNTER_WIDTH)
    ) dma (
        .clk(axi_clk),
        .rst_n(axi_domain_rst_n),
        .desc_valid(axi_desc_valid),
        .desc_ready(axi_desc_ready),
        .desc_src(axi_desc_src),
        .desc_dst(axi_desc_dst),
        .desc_length(axi_desc_length),
        .desc_tag(axi_desc_tag),
        .completion_valid(axi_completion_valid),
        .completion_ready(axi_completion_ready),
        .completion_tag(axi_completion_tag),
        .completion_status(axi_completion_status),
        .arid(arid),
        .araddr(araddr),
        .arlen(arlen),
        .arsize(arsize),
        .arburst(arburst),
        .arlock(arlock),
        .arcache(arcache),
        .arqos(arqos),
        .arregion(arregion),
        .arprot(arprot),
        .arvalid(arvalid),
        .arready(arready),
        .rid(rid),
        .rdata(rdata),
        .rresp(rresp),
        .rlast(rlast),
        .rvalid(rvalid),
        .rready(rready),
        .awid(awid),
        .awaddr(awaddr),
        .awlen(awlen),
        .awsize(awsize),
        .awburst(awburst),
        .awlock(awlock),
        .awcache(awcache),
        .awqos(awqos),
        .awregion(awregion),
        .awprot(awprot),
        .awvalid(awvalid),
        .awready(awready),
        .wdata(wdata),
        .wstrb(wstrb),
        .wlast(wlast),
        .wvalid(wvalid),
        .wready(wready),
        .bid(bid),
        .bresp(bresp),
        .bvalid(bvalid),
        .bready(bready),
        .cycle_count(cycle_count),
        .active_cycle_count(active_cycle_count),
        .descriptor_count(descriptor_count),
        .completion_count(completion_count),
        .error_count(error_count),
        .read_burst_count(read_burst_count),
        .read_beat_count(read_beat_count),
        .write_burst_count(write_burst_count),
        .write_beat_count(write_beat_count),
        .write_response_count(write_response_count),
        .ar_stall_count(ar_stall_count),
        .r_stall_count(r_stall_count),
        .aw_stall_count(aw_stall_count),
        .w_stall_count(w_stall_count),
        .b_stall_count(b_stall_count)
    );
endmodule
`default_nettype wire
