`default_nettype none
// Invalid configurations are isolated from behavioral benches' legal vector sizes.
module tb_extension_parameters;
    timeunit 1ns / 1ps;
    parameter int unsigned KIND = 0;
    parameter int unsigned STAGES = 2;
    parameter int unsigned DATA_WIDTH = 128;
    parameter int unsigned DEPTH = 4;
    parameter int unsigned CHANNELS = 4;
    parameter int unsigned INDEX_WIDTH = 2;
    parameter int unsigned DESCRIPTOR_DEPTH = 2;
    parameter int unsigned COMPLETION_DEPTH = 1;
    parameter int unsigned COUNTER_WIDTH = 64;
    parameter int unsigned TAG_WIDTH = 8;
    parameter int unsigned ID_WIDTH = 1;
    if (KIND == 0) begin : g_kind_0
        reset_sync #(
            .STAGES(STAGES)
        ) dut (
            .clk('0),
            .arst_n('0),
            .rst_n()
        );
    end else if (KIND == 1) begin : g_kind_1
        cdc_bit_sync #(
            .WIDTH(DATA_WIDTH),
            .STAGES(STAGES)
        ) dut (
            .clk('0),
            .rst_n('0),
            .async_data('0),
            .sync_data()
        );
    end else if (KIND == 2) begin : g_kind_2
        dma_async_fifo #(
            .DATA_WIDTH(DATA_WIDTH),
            .DEPTH(DEPTH)
        ) dut (
            .wr_clk('0),
            .wr_rst_n('0),
            .push_data('0),
            .push_valid('0),
            .push_ready(),
            .rd_clk('0),
            .rd_rst_n('0),
            .pop_data(),
            .pop_valid(),
            .pop_ready('0)
        );
    end else if (KIND == 3) begin : g_kind_3
        dma_performance_counters #(
            .COUNTER_WIDTH(COUNTER_WIDTH)
        ) dut (
            .clk('0),
            .rst_n('0),
            .busy('0),
            .start_event('0),
            .finish_event('0),
            .finish_status('0),
            .arvalid('0),
            .arready('0),
            .rvalid('0),
            .rready('0),
            .awvalid('0),
            .awready('0),
            .wvalid('0),
            .wready('0),
            .bvalid('0),
            .bready('0),
            .cycle_count(),
            .active_cycle_count(),
            .descriptor_count(),
            .completion_count(),
            .error_count(),
            .read_burst_count(),
            .read_beat_count(),
            .write_burst_count(),
            .write_beat_count(),
            .write_response_count(),
            .ar_stall_count(),
            .r_stall_count(),
            .aw_stall_count(),
            .w_stall_count(),
            .b_stall_count()
        );
    end else if (KIND == 4) begin : g_kind_4
        axi_dma_multi #(
            .CHANNELS(CHANNELS),
            .DESCRIPTOR_DEPTH(DESCRIPTOR_DEPTH),
            .COMPLETION_DEPTH(COMPLETION_DEPTH),
            .COUNTER_WIDTH(COUNTER_WIDTH),
            .TAG_WIDTH(TAG_WIDTH),
            .ID_WIDTH(ID_WIDTH)
        ) dut (
            .clk('0),
            .rst_n('0),
            .desc_valid('0),
            .desc_ready(),
            .desc_src('0),
            .desc_dst('0),
            .desc_length('0),
            .desc_tag('0),
            .completion_valid(),
            .completion_ready('0),
            .completion_tag(),
            .completion_status(),
            .cycle_count(),
            .active_cycle_count(),
            .descriptor_count(),
            .completion_count(),
            .error_count(),
            .read_burst_count(),
            .read_beat_count(),
            .write_burst_count(),
            .write_beat_count(),
            .write_response_count(),
            .ar_stall_count(),
            .r_stall_count(),
            .aw_stall_count(),
            .w_stall_count(),
            .b_stall_count(),
            .arid(),
            .araddr(),
            .arlen(),
            .arsize(),
            .arburst(),
            .arlock(),
            .arcache(),
            .arqos(),
            .arregion(),
            .arprot(),
            .arvalid(),
            .arready('0),
            .rid('0),
            .rdata('0),
            .rresp('0),
            .rlast('0),
            .rvalid('0),
            .rready(),
            .awid(),
            .awaddr(),
            .awlen(),
            .awsize(),
            .awburst(),
            .awlock(),
            .awcache(),
            .awqos(),
            .awregion(),
            .awprot(),
            .awvalid(),
            .awready('0),
            .wdata(),
            .wstrb(),
            .wlast(),
            .wvalid(),
            .wready('0),
            .bid('0),
            .bresp('0),
            .bvalid('0),
            .bready()
        );
    end else if (KIND == 5) begin : g_kind_5
        axi_dma_cdc #(
            .CHANNELS(CHANNELS),
            .CDC_DEPTH(DEPTH),
            .COUNTER_WIDTH(COUNTER_WIDTH)
        ) dut (
            .ctrl_clk('0),
            .axi_clk('0),
            .ctrl_arst_n('0),
            .axi_arst_n('0),
            .ctrl_domain_rst_n(),
            .axi_domain_rst_n(),
            .desc_valid('0),
            .desc_ready(),
            .desc_src('0),
            .desc_dst('0),
            .desc_length('0),
            .desc_tag('0),
            .completion_valid(),
            .completion_ready('0),
            .completion_tag(),
            .completion_status(),
            .cycle_count(),
            .active_cycle_count(),
            .descriptor_count(),
            .completion_count(),
            .error_count(),
            .read_burst_count(),
            .read_beat_count(),
            .write_burst_count(),
            .write_beat_count(),
            .write_response_count(),
            .ar_stall_count(),
            .r_stall_count(),
            .aw_stall_count(),
            .w_stall_count(),
            .b_stall_count(),
            .arid(),
            .araddr(),
            .arlen(),
            .arsize(),
            .arburst(),
            .arlock(),
            .arcache(),
            .arqos(),
            .arregion(),
            .arprot(),
            .arvalid(),
            .arready('0),
            .rid('0),
            .rdata('0),
            .rresp('0),
            .rlast('0),
            .rvalid('0),
            .rready(),
            .awid(),
            .awaddr(),
            .awlen(),
            .awsize(),
            .awburst(),
            .awlock(),
            .awcache(),
            .awqos(),
            .awregion(),
            .awprot(),
            .awvalid(),
            .awready('0),
            .wdata(),
            .wstrb(),
            .wlast(),
            .wvalid(),
            .wready('0),
            .bid('0),
            .bresp('0),
            .bvalid('0),
            .bready()
        );
    end else if (KIND == 6) begin : g_kind_6
        round_robin_arbiter #(
            .REQUESTERS(CHANNELS),
            .INDEX_WIDTH(INDEX_WIDTH)
        ) dut (
            .clk('0),
            .rst_n('0),
            .request('0),
            .grant_valid(),
            .grant_onehot(),
            .grant_index(),
            .grant_ready('0)
        );
    end
    initial begin
        #1;
        $fatal(1, "invalid extension parameter was not rejected");
    end
endmodule
`default_nettype wire
