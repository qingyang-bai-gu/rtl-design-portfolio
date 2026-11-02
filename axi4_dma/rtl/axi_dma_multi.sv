`default_nettype none
`include "dma_checks.svh"
// Descriptor-granular round robin over independent per-channel descriptor/completion queues.
// Completion credit is reserved at dispatch, so a stalled channel cannot block other owners.
module axi_dma_multi #(
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
    localparam int unsigned CHANNEL_INDEX_WIDTH = CHANNELS <= 1 ? 1 : $clog2(CHANNELS),
    localparam int unsigned DATA_BITS = DATA_WIDTH == 0 ? 1 : DATA_WIDTH,
    localparam int unsigned ID_BITS = ID_WIDTH == 0 ? 1 : ID_WIDTH,
    localparam int unsigned TAG_BITS = TAG_WIDTH == 0 ? 1 : TAG_WIDTH,
    localparam int unsigned STROBE_BITS = DATA_WIDTH < 8 ? 1 : DATA_WIDTH / 8,
    localparam int unsigned COUNTER_BITS = COUNTER_WIDTH == 0 ? 1 : COUNTER_WIDTH
) (
    input logic clk,
    input logic rst_n,
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
    logic [CHANNEL_COUNT-1:0][DESC_BITS-1:0] descriptor_head;
    logic [CHANNEL_COUNT-1:0] descriptor_available;
    logic [CHANNEL_COUNT-1:0] descriptor_pop;
    logic [CHANNEL_COUNT-1:0][COMP_BITS-1:0] completion_head;
    logic [CHANNEL_COUNT-1:0] completion_space;
    logic [CHANNEL_COUNT-1:0] completion_push;
    logic [CHANNEL_COUNT-1:0] request;
    logic grant_valid;
    logic grant_ready;
    logic [CHANNEL_COUNT-1:0] grant_onehot;
    logic [CHANNEL_INDEX_WIDTH-1:0] grant_index;
    logic owner_valid;
    logic [CHANNEL_INDEX_WIDTH-1:0] owner;
    logic [DESC_BITS-1:0] selected_descriptor;
    logic core_desc_valid;
    logic core_desc_ready;
    logic [ADDR_WIDTH-1:0] core_desc_src;
    logic [ADDR_WIDTH-1:0] core_desc_dst;
    logic [ADDR_WIDTH:0] core_desc_length;
    logic [TAG_BITS-1:0] core_desc_tag;
    logic core_completion_valid;
    logic core_completion_ready;
    logic [TAG_BITS-1:0] core_completion_tag;
    logic [1:0] core_completion_status;
    logic start_event;
    logic finish_event;

    assign grant_ready = rst_n && !owner_valid && core_desc_ready;
    assign core_desc_valid = rst_n && !owner_valid && grant_valid;
    assign start_event = core_desc_valid && core_desc_ready;
    assign finish_event = core_completion_valid && core_completion_ready;
    assign {core_desc_src, core_desc_dst, core_desc_length, core_desc_tag} = selected_descriptor;
    always_comb begin
        selected_descriptor = '0;
        core_completion_ready = 1'b0;
        for (int channel = 0; channel < CHANNELS; channel = channel + 1) begin
            if (grant_onehot[channel]) begin
                selected_descriptor = descriptor_head[channel];
            end
            if (owner_valid && owner == CHANNEL_INDEX_WIDTH'(channel)) begin
                core_completion_ready = rst_n && completion_space[channel];
            end
        end
    end

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            owner_valid <= 1'b0;
            owner <= '0;
        end else if (start_event) begin
            owner_valid <= 1'b1;
            owner <= grant_index;
        end else if (finish_event) begin
            owner_valid <= 1'b0;
        end
    end

    for (genvar channel = 0; channel < CHANNELS; channel = channel + 1) begin : g_channel
        assign request[channel] = rst_n && !owner_valid &&
                                  descriptor_available[channel] && completion_space[channel];
        assign descriptor_pop[channel] = grant_ready && grant_valid && grant_onehot[channel];
        assign completion_push[channel] = owner_valid && core_completion_valid &&
                                          owner == CHANNEL_INDEX_WIDTH'(channel);
        assign completion_tag[channel] = completion_head[channel][COMP_BITS-1:2];
        assign completion_status[channel] = completion_head[channel][1:0];
        dma_burst_buffer #(
            .DATA_WIDTH(DESC_BITS),
            .DEPTH(DESCRIPTOR_DEPTH)
        ) descriptors (
            .clk(clk),
            .rst_n(rst_n),
            .flush(1'b0),
            .push_data({
                desc_src[channel], desc_dst[channel], desc_length[channel], desc_tag[channel]
            }),
            .push_valid(desc_valid[channel]),
            .push_ready(desc_ready[channel]),
            .pop_data(descriptor_head[channel]),
            .pop_valid(descriptor_available[channel]),
            .pop_ready(descriptor_pop[channel]),
            .occupancy(),
            .empty(),
            .full()
        );
        dma_burst_buffer #(
            .DATA_WIDTH(COMP_BITS),
            .DEPTH(COMPLETION_DEPTH)
        ) completions (
            .clk(clk),
            .rst_n(rst_n),
            .flush(1'b0),
            .push_data({core_completion_tag, core_completion_status}),
            .push_valid(completion_push[channel]),
            .push_ready(completion_space[channel]),
            .pop_data(completion_head[channel]),
            .pop_valid(completion_valid[channel]),
            .pop_ready(completion_ready[channel]),
            .occupancy(),
            .empty(),
            .full()
        );
    end
    round_robin_arbiter #(
        .REQUESTERS(CHANNELS)
    ) arbiter (
        .clk(clk),
        .rst_n(rst_n),
        .request(request),
        .grant_valid(grant_valid),
        .grant_ready(grant_ready),
        .grant_onehot(grant_onehot),
        .grant_index(grant_index)
    );
    axi_dma #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .MAX_BURST_BEATS(MAX_BURST_BEATS),
        .BUFFER_DEPTH(BUFFER_DEPTH),
        .TAG_WIDTH(TAG_WIDTH),
        .ID_WIDTH(ID_WIDTH)
    ) core (
        .clk(clk),
        .rst_n(rst_n),
        .desc_valid(core_desc_valid),
        .desc_ready(core_desc_ready),
        .desc_src(core_desc_src),
        .desc_dst(core_desc_dst),
        .desc_length(core_desc_length),
        .desc_tag(core_desc_tag),
        .completion_valid(core_completion_valid),
        .completion_ready(core_completion_ready),
        .completion_tag(core_completion_tag),
        .completion_status(core_completion_status),
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
        .bready(bready)
    );
    dma_performance_counters #(
        .COUNTER_WIDTH(COUNTER_WIDTH)
    ) performance (
        .clk(clk),
        .rst_n(rst_n),
        .start_event(start_event),
        .finish_event(finish_event),
        .busy(owner_valid),
        .finish_status(core_completion_status),
        .arvalid(arvalid),
        .arready(arready),
        .rvalid(rvalid),
        .rready(rready),
        .awvalid(awvalid),
        .awready(awready),
        .wvalid(wvalid),
        .wready(wready),
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
`ifndef SYNTHESIS
    initial begin
        `DMA_CHECK_GEOMETRY
        if (CHANNELS == 0 || DESCRIPTOR_DEPTH == 0 || COMPLETION_DEPTH == 0) begin
            $fatal(1, "PARAM: channels and per-channel queue depths must be positive");
        end
    end
`endif
endmodule
`default_nettype wire
