`default_nettype none
// Dedicated elaboration harness: behavioral benches require legal vector widths.
module tb_parameters;
    timeunit 1ns / 1ps;

    parameter int unsigned KIND = 0;
    parameter int unsigned ADDR_WIDTH = 32;
    parameter int unsigned DATA_WIDTH = 128;
    parameter int unsigned MAX_BURST_BEATS = 16;
    parameter int unsigned DEPTH = 16;
    parameter int unsigned ID_WIDTH = 1;
    parameter int unsigned TAG_WIDTH = 8;
    parameter int unsigned MEM_BYTES = 65536;
    generate
        if (KIND == 0) begin : g_planner
            dma_burst_planner #(
                .ADDR_WIDTH(ADDR_WIDTH),
                .DATA_WIDTH(DATA_WIDTH),
                .MAX_BURST_BEATS(MAX_BURST_BEATS)
            ) dut (
                .src_addr('0),
                .dst_addr('0),
                .remaining_bytes('0),
                .plan_valid(),
                .plan_beats(),
                .plan_bytes()
            );
        end else if (KIND == 1) begin : g_reader
            dma_read_engine #(
                .ADDR_WIDTH(ADDR_WIDTH),
                .DATA_WIDTH(DATA_WIDTH),
                .MAX_BURST_BEATS(MAX_BURST_BEATS),
                .ID_WIDTH(ID_WIDTH)
            ) dut (
                .clk(1'b0),
                .rst_n(1'b0),
                .req_valid(1'b0),
                .req_addr('0),
                .req_beats('0),
                .req_id('0),
                .arready(1'b0),
                .rid('0),
                .rdata('0),
                .rresp('0),
                .rlast(1'b0),
                .rvalid(1'b0),
                .data_ready(1'b0),
                .result_ready(1'b0),
                .req_ready(),
                .arid(),
                .araddr(),
                .arlen(),
                .arsize(),
                .arburst(),
                .arvalid(),
                .rready(),
                .data(),
                .data_valid(),
                .result_valid(),
                .result_error()
            );
        end else if (KIND == 2) begin : g_writer
            dma_write_engine #(
                .ADDR_WIDTH(ADDR_WIDTH),
                .DATA_WIDTH(DATA_WIDTH),
                .MAX_BURST_BEATS(MAX_BURST_BEATS),
                .ID_WIDTH(ID_WIDTH)
            ) dut (
                .clk(1'b0),
                .rst_n(1'b0),
                .req_valid(1'b0),
                .req_addr('0),
                .req_beats('0),
                .req_id('0),
                .awready(1'b0),
                .data('0),
                .data_valid(1'b0),
                .wready(1'b0),
                .bid('0),
                .bresp('0),
                .bvalid(1'b0),
                .result_ready(1'b0),
                .req_ready(),
                .awid(),
                .awaddr(),
                .awlen(),
                .awsize(),
                .awburst(),
                .awvalid(),
                .data_ready(),
                .wdata(),
                .wstrb(),
                .wlast(),
                .wvalid(),
                .bready(),
                .result_valid(),
                .result_error()
            );
        end else if (KIND == 3) begin : g_buffer_test
            dma_burst_buffer #(
                .DATA_WIDTH(DATA_WIDTH),
                .DEPTH(DEPTH)
            ) dut (
                .clk(1'b0),
                .rst_n(1'b0),
                .flush(1'b0),
                .push_data('0),
                .push_valid(1'b0),
                .pop_ready(1'b0),
                .push_ready(),
                .pop_data(),
                .pop_valid(),
                .occupancy(),
                .empty(),
                .full()
            );
        end else if (KIND == 4) begin : g_controller_test
            dma_controller #(
                .ADDR_WIDTH(ADDR_WIDTH),
                .DATA_WIDTH(DATA_WIDTH),
                .MAX_BURST_BEATS(MAX_BURST_BEATS),
                .TAG_WIDTH(TAG_WIDTH)
            ) dut (
                .clk(1'b0),
                .rst_n(1'b0),
                .desc_valid(1'b0),
                .desc_src('0),
                .desc_dst('0),
                .desc_length('0),
                .desc_tag('0),
                .completion_ready(1'b0),
                .plan_valid(1'b0),
                .plan_beats('0),
                .plan_bytes('0),
                .buffer_empty(1'b1),
                .read_req_ready(1'b0),
                .read_result_valid(1'b0),
                .read_result_error(1'b0),
                .write_req_ready(1'b0),
                .write_result_valid(1'b0),
                .write_result_error(1'b0),
                .desc_ready(),
                .completion_valid(),
                .completion_tag(),
                .completion_status(),
                .plan_src(),
                .plan_dst(),
                .plan_remaining(),
                .buffer_flush(),
                .read_req_valid(),
                .read_req_addr(),
                .read_req_beats(),
                .read_result_ready(),
                .write_req_valid(),
                .write_req_addr(),
                .write_req_beats(),
                .write_result_ready()
            );
        end else if (KIND == 5) begin : g_wrapper_test
            axi_dma #(
                .ADDR_WIDTH(ADDR_WIDTH),
                .DATA_WIDTH(DATA_WIDTH),
                .MAX_BURST_BEATS(MAX_BURST_BEATS),
                .BUFFER_DEPTH(DEPTH),
                .TAG_WIDTH(TAG_WIDTH),
                .ID_WIDTH(ID_WIDTH)
            ) dut (
                .clk(1'b0),
                .rst_n(1'b0),
                .desc_valid(1'b0),
                .desc_src('0),
                .desc_dst('0),
                .desc_length('0),
                .desc_tag('0),
                .completion_ready(1'b0),
                .arready(1'b0),
                .rid('0),
                .rdata('0),
                .rresp('0),
                .rlast(1'b0),
                .rvalid(1'b0),
                .awready(1'b0),
                .wready(1'b0),
                .bid('0),
                .bresp('0),
                .bvalid(1'b0),
                .desc_ready(),
                .completion_valid(),
                .completion_tag(),
                .completion_status(),
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
                .wdata(),
                .wstrb(),
                .wlast(),
                .wvalid(),
                .bready()
            );
        end else if (KIND == 6) begin : g_memory_test
            axi_memory_model #(
                .ADDR_WIDTH(ADDR_WIDTH),
                .DATA_WIDTH(DATA_WIDTH),
                .ID_WIDTH(ID_WIDTH),
                .MEM_BYTES(MEM_BYTES)
            ) dut (
                .clk(1'b0),
                .rst_n(1'b0),
                .cfg_ar_delay('0),
                .cfg_r_delay('0),
                .cfg_aw_delay('0),
                .cfg_w_delay('0),
                .cfg_b_delay('0),
                .cfg_r_resp('0),
                .cfg_b_resp('0),
                .cfg_r_bad_id(1'b0),
                .cfg_b_bad_id(1'b0),
                .arid('0),
                .araddr('0),
                .arlen('0),
                .arsize('0),
                .arburst('0),
                .arvalid(1'b0),
                .rready(1'b0),
                .awid('0),
                .awaddr('0),
                .awlen('0),
                .awsize('0),
                .awburst('0),
                .awvalid(1'b0),
                .wdata('0),
                .wstrb('0),
                .wlast(1'b0),
                .wvalid(1'b0),
                .bready(1'b0),
                .arready(),
                .rid(),
                .rdata(),
                .rresp(),
                .rlast(),
                .rvalid(),
                .awready(),
                .wready(),
                .bid(),
                .bresp(),
                .bvalid()
            );
        end
    endgenerate

    initial begin
        #1;
        $fatal(1, "invalid parameter was not rejected");
    end

endmodule
`default_nettype wire
