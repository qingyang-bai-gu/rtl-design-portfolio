`default_nettype none
// The same external-interface scoreboard exercises single-clock and dual-clock wrappers.
module tb_multi;
    timeunit 1ns / 1ps;
    parameter int unsigned CHANNELS = 4;
    parameter int unsigned ADDR_WIDTH = 32;
    parameter int unsigned DATA_WIDTH = 128;
    parameter int unsigned MAX_BURST_BEATS = 16;
    parameter int unsigned DESCRIPTOR_DEPTH = 2;
    parameter int unsigned COMPLETION_DEPTH = 1;
    parameter bit CDC_ENABLE = 0;
    parameter int unsigned CDC_DEPTH = 4;
    parameter int unsigned AR_DELAY = 2;
    parameter int unsigned R_DELAY = 1;
    parameter int unsigned AW_DELAY = 0;
    parameter int unsigned W_DELAY = 2;
    parameter int unsigned B_DELAY = 3;
    parameter int unsigned CTRL_HALF = 3;
    parameter int unsigned AXI_HALF = 5;
    parameter int unsigned AXI_PHASE = 0;
    localparam int unsigned TAG_WIDTH = 8;
    localparam int unsigned ID_WIDTH = 1;
    localparam int unsigned DATA_BITS = DATA_WIDTH;
    localparam int unsigned ID_BITS = ID_WIDTH;
    localparam int unsigned TAG_BITS = TAG_WIDTH;
    localparam int unsigned STROBE_BITS = DATA_WIDTH / 8;
    localparam int unsigned COUNTER_WIDTH = 32;
    localparam int unsigned BB = DATA_WIDTH / 8;
    localparam logic [2:0] AXI_SIZE = 3'($clog2(BB));
    localparam int unsigned MEM_BYTES = ADDR_WIDTH == 12 ? 4096 : 131072;
    localparam int unsigned REGION = ADDR_WIDTH == 12 ? 512 : 16384;
    localparam int unsigned MAX_RECORDS = 256;
    localparam int unsigned CHUNK = MAX_BURST_BEATS < 4096 / BB ? MAX_BURST_BEATS : 4096 / BB;
    localparam int unsigned RANDOM_BEATS = REGION / 4 / BB < 64 ? REGION / 4 / BB : 64;
    logic clk = 0;
    logic ctrl_clk;
    logic axi_clock_enable = 1;
    logic ctrl_clock_enable = 1;
    logic control_reset_request = 0;
    logic axi_reset_request = 0;
    logic rst_n;
    logic ctrl_rst_n;
    logic [CHANNELS-1:0] desc_valid = '0;
    logic [CHANNELS-1:0] desc_ready;
    logic [CHANNELS-1:0][ADDR_WIDTH-1:0] desc_src = '0;
    logic [CHANNELS-1:0][ADDR_WIDTH-1:0] desc_dst = '0;
    logic [CHANNELS-1:0][ADDR_WIDTH:0] desc_length = '0;
    logic [CHANNELS-1:0][TAG_BITS-1:0] desc_tag = '0;
    logic [CHANNELS-1:0] completion_valid;
    logic [CHANNELS-1:0] completion_ready = '0;
    logic [CHANNELS-1:0][TAG_BITS-1:0] completion_tag;
    logic [CHANNELS-1:0][1:0] completion_status;
    logic [ID_BITS-1:0] arid;
    logic [ADDR_WIDTH-1:0] araddr;
    logic [7:0] arlen;
    logic [2:0] arsize;
    logic [1:0] arburst;
    logic arlock;
    logic [3:0] arcache;
    logic [3:0] arqos;
    logic [3:0] arregion;
    logic [2:0] arprot;
    logic arvalid;
    logic arready;
    logic [ID_BITS-1:0] rid;
    logic [DATA_BITS-1:0] rdata;
    logic [1:0] rresp;
    logic rlast;
    logic rvalid;
    logic rready;
    logic [ID_BITS-1:0] awid;
    logic [ADDR_WIDTH-1:0] awaddr;
    logic [7:0] awlen;
    logic [2:0] awsize;
    logic [1:0] awburst;
    logic awlock;
    logic [3:0] awcache;
    logic [3:0] awqos;
    logic [3:0] awregion;
    logic [2:0] awprot;
    logic awvalid;
    logic awready;
    logic [DATA_BITS-1:0] wdata;
    logic [STROBE_BITS-1:0] wstrb;
    logic wlast;
    logic wvalid;
    logic wready;
    logic [ID_BITS-1:0] bid;
    logic [1:0] bresp;
    logic bvalid;
    logic bready;
    logic [COUNTER_WIDTH-1:0] cycle_count;
    logic [COUNTER_WIDTH-1:0] active_cycle_count;
    logic [COUNTER_WIDTH-1:0] descriptor_count;
    logic [COUNTER_WIDTH-1:0] completion_count;
    logic [COUNTER_WIDTH-1:0] error_count;
    logic [COUNTER_WIDTH-1:0] read_burst_count;
    logic [COUNTER_WIDTH-1:0] read_beat_count;
    logic [COUNTER_WIDTH-1:0] write_burst_count;
    logic [COUNTER_WIDTH-1:0] write_beat_count;
    logic [COUNTER_WIDTH-1:0] write_response_count;
    logic [COUNTER_WIDTH-1:0] ar_stall_count;
    logic [COUNTER_WIDTH-1:0] r_stall_count;
    logic [COUNTER_WIDTH-1:0] aw_stall_count;
    logic [COUNTER_WIDTH-1:0] w_stall_count;
    logic [COUNTER_WIDTH-1:0] b_stall_count;
    logic [15:0] cfg_ar_delay = 16'(AR_DELAY);
    logic [15:0] cfg_r_delay = 16'(R_DELAY);
    logic [15:0] cfg_aw_delay = 16'(AW_DELAY);
    logic [15:0] cfg_w_delay = 16'(W_DELAY);
    logic [15:0] cfg_b_delay = 16'(B_DELAY);
    logic inject_read = 0;
    logic inject_write = 0;
    logic inject_id = 0;
    logic [ADDR_WIDTH-1:0] read_fault_addr = 0;
    logic [ADDR_WIDTH-1:0] write_fault_addr = 0;
    logic [1:0] cfg_r_resp;
    logic [1:0] cfg_b_resp;
    logic cfg_r_bad_id;
    logic cfg_b_bad_id;
    assign cfg_r_resp = inject_read && araddr == read_fault_addr && !inject_id ? 2'b10 : 2'b00;
    assign cfg_b_resp = inject_write && awaddr == write_fault_addr && !inject_id ? 2'b11 : 2'b00;
    assign cfg_r_bad_id = inject_read && araddr == read_fault_addr && inject_id;
    assign cfg_b_bad_id = inject_write && awaddr == write_fault_addr && inject_id;
    logic run_producers = 0;
    logic random_ready = 0;
    logic [CHANNELS-1:0] completion_mask = '1;
    int scenario = 0;
    int target[CHANNELS];
    int batch_base[CHANNELS];
    int sent[CHANNELS];
    int tail[CHANNELS];
    int received[CHANNELS];
    int bus_head[CHANNELS];
    logic [CHANNELS-1:0] accepted_last = '0;
    int offer_status[CHANNELS];
    int offer_fail_chunk[CHANNELS];
    int gold_src[CHANNELS][MAX_RECORDS];
    int gold_dst[CHANNELS][MAX_RECORDS];
    int gold_length[CHANNELS][MAX_RECORDS];
    int gold_status[CHANNELS][MAX_RECORDS];
    logic [TAG_WIDTH-1:0] gold_tag[CHANNELS][MAX_RECORDS];
    logic [7:0] expected_memory[MEM_BYTES];
    logic [31:0] producer_rng = 32'h47C4A11E;
    logic [31:0] consumer_rng = 32'hC0A51DE5;
    int expected_ar = 0;
    int expected_r = 0;
    int expected_aw = 0;
    int expected_w = 0;
    int expected_b = 0;
    int expected_errors = 0;
    int expected_active = 0;
    int observed_ar = 0;
    int observed_r = 0;
    int observed_aw = 0;
    int observed_w = 0;
    int observed_b = 0;
    int observed_ar_stall = 0;
    int observed_r_stall = 0;
    int observed_aw_stall = 0;
    int observed_w_stall = 0;
    int observed_b_stall = 0;
    int axi_cycles = 0;
    int phase = 0;
    bit active_descriptor = 0;
    int current_channel = 0;
    int current_status = 0;
    int current_src = 0;
    int current_dst = 0;
    int remaining = 0;
    int planned_beats = 0;
    int read_index = 0;
    int write_index = 0;
    bit read_failed = 0;
    bit check_fair_order = 0;
    int descriptor_order = 0;
    int checks = 0;

    initial begin
        #(AXI_PHASE);
        forever begin
            #(AXI_HALF);
            if (axi_clock_enable) begin
                clk = !clk;
            end else begin
                clk = 0;
            end
        end
    end
    if (CDC_ENABLE) begin : g_control_clock
        initial begin
            ctrl_clk = 0;
            forever begin
                #(CTRL_HALF);
                if (ctrl_clock_enable) begin
                    ctrl_clk = !ctrl_clk;
                end else begin
                    ctrl_clk = 0;
                end
            end
        end
    end else begin : g_shared_clock
        assign ctrl_clk = clk;
        assign rst_n = control_reset_request && axi_reset_request;
        assign ctrl_rst_n = rst_n;
    end
    if (!CDC_ENABLE) begin : g_single
        axi_dma_multi #(
            .CHANNELS(CHANNELS),
            .ADDR_WIDTH(ADDR_WIDTH),
            .DATA_WIDTH(DATA_WIDTH),
            .MAX_BURST_BEATS(MAX_BURST_BEATS),
            .TAG_WIDTH(TAG_WIDTH),
            .ID_WIDTH(ID_WIDTH),
            .DESCRIPTOR_DEPTH(DESCRIPTOR_DEPTH),
            .COMPLETION_DEPTH(COMPLETION_DEPTH),
            .COUNTER_WIDTH(COUNTER_WIDTH)
        ) dut (
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
    end else begin : g_dual
        axi_dma_cdc #(
            .CHANNELS(CHANNELS),
            .ADDR_WIDTH(ADDR_WIDTH),
            .DATA_WIDTH(DATA_WIDTH),
            .MAX_BURST_BEATS(MAX_BURST_BEATS),
            .TAG_WIDTH(TAG_WIDTH),
            .ID_WIDTH(ID_WIDTH),
            .DESCRIPTOR_DEPTH(DESCRIPTOR_DEPTH),
            .COMPLETION_DEPTH(COMPLETION_DEPTH),
            .COUNTER_WIDTH(COUNTER_WIDTH),
            .CDC_DEPTH(CDC_DEPTH)
        ) dut (
            .ctrl_clk(ctrl_clk),
            .axi_clk(clk),
            .ctrl_arst_n(control_reset_request),
            .axi_arst_n(axi_reset_request),
            .ctrl_domain_rst_n(ctrl_rst_n),
            .axi_domain_rst_n(rst_n),
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
    end
    axi_memory_model #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .MEM_BYTES(MEM_BYTES)
    ) memory (
        .clk(clk),
        .rst_n(rst_n),
        .cfg_ar_delay(cfg_ar_delay),
        .cfg_r_delay(cfg_r_delay),
        .cfg_aw_delay(cfg_aw_delay),
        .cfg_w_delay(cfg_w_delay),
        .cfg_b_delay(cfg_b_delay),
        .cfg_r_resp(cfg_r_resp),
        .cfg_b_resp(cfg_b_resp),
        .cfg_r_bad_id(cfg_r_bad_id),
        .cfg_b_bad_id(cfg_b_bad_id),
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
        .awid(awid),
        .awaddr(awaddr),
        .awlen(awlen),
        .awsize(awsize),
        .awburst(awburst),
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
    for (genvar channel = 0; channel < CHANNELS; channel = channel + 1) begin : g_protocol
        rv_stability #(
            .WIDTH(3 * ADDR_WIDTH + 1 + TAG_WIDTH)
        ) descriptor_hold (
            .clk(ctrl_clk),
            .rst_n(ctrl_rst_n),
            .valid(desc_valid[channel]),
            .ready(desc_ready[channel]),
            .payload({
                desc_src[channel], desc_dst[channel], desc_length[channel], desc_tag[channel]
            })
        );
        rv_stability #(
            .WIDTH(TAG_WIDTH + 2)
        ) completion_hold (
            .clk(ctrl_clk),
            .rst_n(ctrl_rst_n),
            .valid(completion_valid[channel]),
            .ready(completion_ready[channel]),
            .payload({completion_tag[channel], completion_status[channel]})
        );
    end
    rv_stability #(
        .WIDTH(ADDR_WIDTH + ID_WIDTH + 29)
    ) ar_hold (
        .clk(clk),
        .rst_n(rst_n),
        .valid(arvalid),
        .ready(arready),
        .payload({araddr, arid, arlen, arsize, arburst, arlock, arcache, arprot, arqos, arregion})
    );
    rv_stability #(
        .WIDTH(ADDR_WIDTH + ID_WIDTH + 29)
    ) aw_hold (
        .clk(clk),
        .rst_n(rst_n),
        .valid(awvalid),
        .ready(awready),
        .payload({awaddr, awid, awlen, awsize, awburst, awlock, awcache, awprot, awqos, awregion})
    );
    rv_stability #(
        .WIDTH(DATA_WIDTH + ID_WIDTH + 3)
    ) r_hold (
        .clk(clk),
        .rst_n(rst_n),
        .valid(rvalid),
        .ready(rready),
        .payload({rdata, rid, rresp, rlast})
    );
    rv_stability #(
        .WIDTH(DATA_WIDTH + BB + 1)
    ) w_hold (
        .clk(clk),
        .rst_n(rst_n),
        .valid(wvalid),
        .ready(wready),
        .payload({wdata, wstrb, wlast})
    );
    rv_stability #(
        .WIDTH(ID_WIDTH + 2)
    ) b_hold (
        .clk(clk),
        .rst_n(rst_n),
        .valid(bvalid),
        .ready(bready),
        .payload({bid, bresp})
    );
    function automatic int plan_count(input int source, input int destination, input int length);
        int bytes;
        bytes = length;
        if (bytes > MAX_BURST_BEATS * BB) begin
            bytes = MAX_BURST_BEATS * BB;
        end
        if (bytes > 4096 - source % 4096) begin
            bytes = 4096 - source % 4096;
        end
        if (bytes > 4096 - destination % 4096) begin
            bytes = 4096 - destination % 4096;
        end
        return bytes / BB;
    endfunction

    // Independent acceptance ledger. Only this clock-domain observer writes tail/received.
    always @(posedge ctrl_clk or negedge ctrl_rst_n) begin : control_scoreboard
        int count;
        int source;
        int destination;
        int left;
        int chunk_number;
        int body_cycles;
        logic [1:0] expected_status;
        if (!ctrl_rst_n) begin
            accepted_last = '0;
            expected_ar = 0;
            expected_r = 0;
            expected_aw = 0;
            expected_w = 0;
            expected_b = 0;
            expected_errors = 0;
            expected_active = 0;
            for (int channel = 0; channel < CHANNELS; channel = channel + 1) begin
                tail[channel] = 0;
                received[channel] = 0;
            end
        end else begin
            for (int channel = 0; channel < CHANNELS; channel = channel + 1) begin
                accepted_last[channel] = desc_valid[channel] && desc_ready[channel];
                if (accepted_last[channel]) begin
                    if (tail[channel] >= MAX_RECORDS) begin
                        $fatal(1, "multi scoreboard capacity");
                    end
                    source = int'(desc_src[channel]);
                    destination = int'(desc_dst[channel]);
                    left = int'(desc_length[channel]);
                    gold_src[channel][tail[channel]] = source;
                    gold_dst[channel][tail[channel]] = destination;
                    gold_length[channel][tail[channel]] = left;
                    gold_status[channel][tail[channel]] = offer_status[channel];
                    gold_tag[channel][tail[channel]] = desc_tag[channel];
                    tail[channel] = tail[channel] + 1;
                    if (offer_status[channel] != 0) begin
                        expected_errors = expected_errors + 1;
                    end
                    $display("MODEL_DESC %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d", source,
                             destination, left, offer_status[channel], offer_fail_chunk[channel],
                             cfg_ar_delay, cfg_r_delay, cfg_aw_delay, cfg_w_delay, cfg_b_delay);
                    if (offer_status[channel] == 1) begin
                        expected_active = expected_active + 1;
                    end else begin
                        chunk_number = 0;
                        while (left > 0) begin
                            count = plan_count(source, destination, left);
                            expected_ar = expected_ar + 1;
                            expected_r = expected_r + count;
                            if (offer_status[channel] == 2 &&
                                chunk_number == offer_fail_chunk[channel]) begin
                                expected_active = expected_active + 2*count+6+
                                    int'(cfg_ar_delay)+count*int'(cfg_r_delay);
                                left = 0;
                            end else begin
                                expected_aw = expected_aw + 1;
                                expected_w = expected_w + count;
                                expected_b = expected_b + 1;
                                body_cycles = 3*count+9+int'(cfg_ar_delay)+
                                    count*int'(cfg_r_delay)+int'(cfg_aw_delay)+
                                    count*int'(cfg_w_delay)+int'(cfg_b_delay);
                                expected_active = expected_active + body_cycles;
                                left = left - count * BB;
                                if ((offer_status[channel] == 3 &&
                                    chunk_number == offer_fail_chunk[channel]) || left == 0) begin
                                    expected_active = expected_active + 1;
                                    left = 0;
                                end else begin
                                    source = source + count * BB;
                                    destination = destination + count * BB;
                                end
                            end
                            chunk_number = chunk_number + 1;
                        end
                    end
                end
                if (completion_valid[channel] && completion_ready[channel]) begin
                    if (received[channel] >= tail[channel]) begin
                        $fatal(1, "multi unexpected completion channel=%0d", channel);
                    end
                    expected_status = 2'(gold_status[channel][received[channel]]);
                    if (completion_tag[channel] !== gold_tag[channel][received[channel]] ||
                        completion_status[channel] !== expected_status) begin
                        $fatal(1, "multi completion routing/order channel=%0d index=%0d", channel,
                               received[channel]);
                    end
                    if (gold_status[channel][received[channel]] != 1 &&
                        bus_head[channel] <= received[channel]) begin
                        $fatal(1, "multi completion before this channel's AXI work finished");
                    end
                    received[channel] = received[channel] + 1;
                end
            end
        end
    end

    // One AXI observer owns all byte-image updates and burst-progress state.
    always @(posedge clk or negedge rst_n) begin : axi_scoreboard
        int channel;
        int lane;
        int source_byte;
        int destination_byte;
        if (!rst_n) begin
            phase = 0;
            active_descriptor = 0;
            descriptor_order = 0;
            observed_ar = 0;
            observed_r = 0;
            observed_aw = 0;
            observed_w = 0;
            observed_b = 0;
            observed_ar_stall = 0;
            observed_r_stall = 0;
            observed_aw_stall = 0;
            observed_w_stall = 0;
            observed_b_stall = 0;
            axi_cycles = 0;
            for (int i = 0; i < CHANNELS; i = i + 1) begin
                bus_head[i] = 0;
            end
        end else begin
            axi_cycles = axi_cycles + 1;
            if (arvalid && !arready) begin
                observed_ar_stall = observed_ar_stall + 1;
            end
            if (rvalid && !rready) begin
                observed_r_stall = observed_r_stall + 1;
            end
            if (awvalid && !awready) begin
                observed_aw_stall = observed_aw_stall + 1;
            end
            if (wvalid && !wready) begin
                observed_w_stall = observed_w_stall + 1;
            end
            if (bvalid && !bready) begin
                observed_b_stall = observed_b_stall + 1;
            end
            if (arvalid && arready) begin
                if (phase != 0) begin
                    $fatal(1, "multi overlapping AXI bursts");
                end
                if (!active_descriptor) begin
                    channel = int'(araddr) / REGION;
                    if (channel < 0 || channel >= CHANNELS) begin
                        $fatal(1, "multi AR outside channel regions");
                    end
                    while (bus_head[channel] < tail[channel] &&
                           gold_status[channel][bus_head[channel]] == 1) begin
                        bus_head[channel] = bus_head[channel] + 1;
                    end
                    if (bus_head[channel] >= tail[channel]) begin
                        $fatal(1, "multi unrequested AXI read channel=%0d", channel);
                    end
                    if (check_fair_order && channel != descriptor_order % CHANNELS) begin
                        $fatal(1, "multi saturated round-robin order");
                    end
                    descriptor_order = descriptor_order + 1;
                    current_channel = channel;
                    current_src = gold_src[channel][bus_head[channel]];
                    current_dst = gold_dst[channel][bus_head[channel]];
                    remaining = gold_length[channel][bus_head[channel]];
                    current_status = gold_status[channel][bus_head[channel]];
                    active_descriptor = 1;
                end
                planned_beats = plan_count(current_src, current_dst, remaining);
                if ((araddr !== ADDR_WIDTH'(current_src) || arlen !== 8'(planned_beats-1)) ||
                    (arid != 0 || arburst != 1 || arsize != AXI_SIZE) ||
                    {arlock, arcache, arprot, arqos, arregion} != 0) begin
                    $fatal(1, "multi AR oracle channel=%0d", current_channel);
                end
                read_failed = 0;
                read_index = 0;
                observed_ar = observed_ar + 1;
                phase = 1;
            end
            if (rvalid && rready) begin
                if (phase != 1 || rlast !== (read_index == planned_beats - 1)) begin
                    $fatal(1, "multi R count/sequence");
                end
                for (lane = 0; lane < BB; lane = lane + 1) begin
                    if (rdata[lane*8+:8] !== expected_memory[current_src+read_index*BB+lane]) begin
                        $fatal(1, "multi R byte oracle");
                    end
                end
                if (rresp != 0 || rid != 0) begin
                    read_failed = 1;
                end
                read_index = read_index + 1;
                observed_r = observed_r + 1;
                if (read_index == planned_beats) begin
                    if (read_failed) begin
                        if (current_status != 2) begin
                            $fatal(1, "multi unexpected read error");
                        end
                        bus_head[current_channel] = bus_head[current_channel] + 1;
                        active_descriptor = 0;
                        phase = 0;
                    end else begin
                        phase = 2;
                    end
                end
            end
            if (awvalid && awready) begin
                if (phase != 2 || awaddr !== ADDR_WIDTH'(current_dst) ||
                    awlen !== 8'(planned_beats-1) || awid != 0 || awburst != 1 ||
                    awsize != AXI_SIZE || {awlock, awcache, awprot, awqos, awregion} != 0) begin
                    $fatal(1, "multi AW ownership/oracle");
                end
                write_index = 0;
                observed_aw = observed_aw + 1;
                phase = 3;
            end
            if (wvalid && wready) begin
                if (phase != 3 || wlast !== (write_index == planned_beats-1) || wstrb !== '1) begin
                    $fatal(1, "multi W sequence/strobes/last");
                end
                for (lane = 0; lane < BB; lane = lane + 1) begin
                    source_byte = current_src + write_index * BB + lane;
                    if (source_byte < 0 || source_byte >= MEM_BYTES) begin
                        $fatal(1, "multi source byte bounds");
                    end
                    destination_byte = current_dst + write_index * BB + lane;
                    if (destination_byte < 0 || destination_byte >= MEM_BYTES) begin
                        $fatal(1, "multi destination byte bounds");
                    end
                    if (wdata[lane*8+:8] !== expected_memory[source_byte]) begin
                        $fatal(1, "multi W byte oracle channel=%0d dst=%0d", current_channel,
                               destination_byte);
                    end
                    expected_memory[destination_byte] = expected_memory[source_byte];
                end
                observed_w = observed_w + 1;
                write_index = write_index + 1;
                if (write_index == planned_beats) begin
                    phase = 4;
                end
            end
            if (bvalid && bready) begin
                if (phase != 4) begin
                    $fatal(1, "multi B before accepted final W");
                end
                observed_b = observed_b + 1;
                if (bresp != 0 || bid != 0) begin
                    if (current_status != 3) begin
                        $fatal(1, "multi unexpected write error");
                    end
                    bus_head[current_channel] = bus_head[current_channel] + 1;
                    active_descriptor = 0;
                end else begin
                    remaining = remaining - planned_beats * BB;
                    current_src = current_src + planned_beats * BB;
                    current_dst = current_dst + planned_beats * BB;
                    if (remaining == 0) begin
                        if (current_status != 0) begin
                            $fatal(1, "multi expected an injected error");
                        end
                        bus_head[current_channel] = bus_head[current_channel] + 1;
                        active_descriptor = 0;
                    end
                end
                phase = 0;
            end
        end
    end

    // Offers are changed only after acceptance. Each producer's metadata has the same lifetime.
    always @(negedge ctrl_clk or negedge ctrl_rst_n) begin : producers
        int offset;
        int source;
        int destination;
        int beats;
        int local_sequence;
        if (!ctrl_rst_n) begin
            desc_valid = '0;
            for (int channel = 0; channel < CHANNELS; channel = channel + 1) begin
                sent[channel] = 0;
                offer_status[channel] = 0;
                offer_fail_chunk[channel] = 0;
            end
        end else begin
            for (int channel = 0; channel < CHANNELS; channel = channel + 1) begin
                if (accepted_last[channel]) begin
                    desc_valid[channel] = 0;
                    sent[channel] = sent[channel] + 1;
                end
                if (run_producers && !desc_valid[channel] && sent[channel] < target[channel]) begin
                    producer_rng = producer_rng ^ (producer_rng << 13);
                    producer_rng = producer_rng ^ (producer_rng >> 17);
                    producer_rng = producer_rng ^ (producer_rng << 5);
                    offset = ((sent[channel] % 4) * (REGION / 16) / BB) * BB;
                    source = channel * REGION + offset;
                    destination = channel * REGION + REGION / 2 + offset;
                    beats = 1 + int'(producer_rng % RANDOM_BEATS);
                    local_sequence = sent[channel] - batch_base[channel];
                    offer_status[channel] = 0;
                    offer_fail_chunk[channel] = 0;
                    if (scenario == 0) begin
                        beats = RANDOM_BEATS < 3 ? RANDOM_BEATS : 3;
                    end
                    if (scenario == 1 && REGION >= 16384) begin
                        source = channel * REGION + 4096 - BB;
                        destination = channel * REGION + REGION / 2 + 4096 - 2 * BB;
                        beats = 6;
                    end
                    if (scenario == 2 && local_sequence % 2 == 0) begin
                        offer_status[channel] = 1;
                        case (channel % 3)
                            0: beats = 0;
                            1: begin
                                if (BB > 1) begin
                                    source = source + 1;
                                end else begin
                                    beats = 0;
                                end
                            end
                            default: destination = source;
                        endcase
                    end
                    if ((scenario == 3 || scenario == 4) && channel == 0) begin
                        source = 0;
                        destination = REGION / 2;
                        beats = CHUNK + 3;
                        offer_status[channel] = scenario == 3 ? 2 : 3;
                        offer_fail_chunk[channel] = 1;
                    end
                    if (scenario == 6) begin
                        beats = RANDOM_BEATS;
                    end
                    if (source < 0 || destination < 0 || source+beats*BB > MEM_BYTES ||
                        destination+beats*BB > MEM_BYTES) begin
                        $fatal(1, "multi fixture address bounds");
                    end
                    desc_src[channel] = ADDR_WIDTH'(source);
                    desc_dst[channel] = ADDR_WIDTH'(destination);
                    desc_length[channel] = (ADDR_WIDTH + 1)'(beats * BB);
                    desc_tag[channel] = local_sequence == 0 ? 8'hA5 :
                                        8'(sent[channel]*17+channel*31);
                    desc_valid[channel] = 1;
                end
            end
        end
    end
    always @(negedge ctrl_clk or negedge ctrl_rst_n) begin
        if (!ctrl_rst_n) begin
            completion_ready = '0;
        end else begin
            for (int channel = 0; channel < CHANNELS; channel = channel + 1) begin
                consumer_rng = consumer_rng ^ (consumer_rng << 13);
                consumer_rng = consumer_rng ^ (consumer_rng >> 17);
                consumer_rng = consumer_rng ^ (consumer_rng << 5);
                completion_ready[channel] = completion_mask[channel] &&
                                           (!random_ready || consumer_rng[2:0] != 0);
            end
        end
    end

    task automatic ctrl_tick();
        @(posedge ctrl_clk);
        #1;
        @(negedge ctrl_clk);
        #0.1;
    endtask
    task automatic check_memory();
        for (int i = 0; i < MEM_BYTES; i = i + 1) begin
            if (memory.mem[i] !== expected_memory[i]) begin
                $fatal(1, "multi whole-memory mismatch byte=%0d", i);
            end
        end
    endtask
    task automatic begin_batch(input int count, input int mode);
        scenario = mode;
        for (int i = 0; i < CHANNELS; i = i + 1) begin
            batch_base[i] = sent[i];
            target[i] = sent[i] + count;
        end
        run_producers = 1;
    endtask
    task automatic wait_drained();
        bit drained;
        int total;
        drained = 0;
        while (!drained) begin
            ctrl_tick();
            drained = 1;
            for (int i = 0; i < CHANNELS; i = i + 1) begin
                if (received[i] != target[i]) begin
                    drained = 0;
                end
            end
        end
        run_producers = 0;
        repeat (5) begin
            ctrl_tick();
        end
        total = 0;
        for (int i = 0; i < CHANNELS; i = i + 1) begin
            total = total + tail[i];
        end
        if (observed_ar != expected_ar || observed_r != expected_r ||
            observed_aw != expected_aw ||
            (observed_w != expected_w || observed_b != expected_b)) begin
            $fatal(1, {"multi channel counts got=%0d/%0d/%0d/%0d/%0d ",
                       "expected=%0d/%0d/%0d/%0d/%0d"}, observed_ar, observed_r, observed_aw,
                   observed_w, observed_b, expected_ar, expected_r, expected_aw, expected_w,
                   expected_b);
        end
        if (descriptor_count !== 32'(total) || completion_count !== 32'(total) ||
            error_count !== 32'(expected_errors) || active_cycle_count !== 32'(expected_active) ||
            read_burst_count !== 32'(observed_ar) || read_beat_count !== 32'(observed_r) ||
            write_burst_count !== 32'(observed_aw) || write_beat_count !== 32'(observed_w) ||
            write_response_count !== 32'(observed_b) || cycle_count !== 32'(axi_cycles) ||
            ar_stall_count !== 32'(observed_ar_stall) || r_stall_count !== 32'(observed_r_stall) ||
            aw_stall_count !== 32'(observed_aw_stall) || w_stall_count !== 32'(observed_w_stall) ||
            b_stall_count !== 32'(observed_b_stall)) begin
            $fatal(1, "multi performance counters active got=%0d expected=%0d descriptors=%0d/%0d",
                   active_cycle_count, expected_active, descriptor_count, total);
        end
        $display("MODEL_MEASURE %0d", active_cycle_count);
        check_memory();
        checks = checks + 1;
    endtask
    task automatic assert_reset(input bit from_control);
        run_producers = 0;
        #0.2;
        if (from_control) begin
            control_reset_request = 0;
        end else begin
            axi_reset_request = 0;
        end
        #1;
        if (arvalid || awvalid || wvalid || rready || bready || desc_ready != '0 ||
            completion_valid != '0) begin
            $fatal(1, "multi reset suppression");
        end
        $display("MODEL_RESET");
        check_memory();
        for (int i = 0; i < CHANNELS; i = i + 1) begin
            target[i] = 0;
            batch_base[i] = 0;
        end
    endtask
    task automatic release_reset();
        #(10 * (CTRL_HALF + AXI_HALF));
        control_reset_request = 1;
        axi_reset_request = 1;
        wait (rst_n && ctrl_rst_n);
        repeat (12) begin
            ctrl_tick();
        end
        if (completion_valid != '0) begin
            $fatal(1, "multi completion survived reset");
        end
    endtask
    initial begin
        #50000000;
        $fatal(1, "multi watchdog CDC=%0d phase=%0d received0=%0d target0=%0d", CDC_ENABLE, phase,
               received[0], target[0]);
    end
    initial begin
        for (int i = 0; i < MEM_BYTES; i = i + 1) begin
            expected_memory[i] = 8'((i * 29) ^ (i >> 8) ^ ((i >> 12) * 7));
            memory.mem[i] = expected_memory[i];
        end
        for (int i = 0; i < CHANNELS; i = i + 1) begin
            target[i] = 0;
            batch_base[i] = 0;
        end
        release_reset();
        $display("MODEL_RESET");
        check_fair_order = 1;
        begin_batch(3, 0);
        wait_drained();
        check_fair_order = 0;
        begin_batch(1, 1);
        wait_drained();
        // Hold channel zero's completion while all other owners keep making progress.
        completion_mask[0] = 0;
        begin_batch(8, 0);
        begin : wait_other_channels
            bit others_done;
            others_done = 0;
            while (!others_done) begin
                ctrl_tick();
                others_done = 1;
                for (int i = 1; i < CHANNELS; i = i + 1) begin
                    if (received[i] != target[i]) begin
                        others_done = 0;
                    end
                end
            end
        end
        while (!completion_valid[0]) begin
            ctrl_tick();
        end
        repeat (30) begin
            ctrl_tick();
        end
        if (!completion_valid[0]) begin
            $fatal(1, "multi expected stalled completion");
        end
        completion_mask = '1;
        wait_drained();
        random_ready = 1;
        begin_batch(24, 5);
        wait_drained();
        begin_batch(6, 2);
        wait_drained();
        for (int fault_id = 0; fault_id < 2; fault_id = fault_id + 1) begin
            inject_id = fault_id != 0;
            read_fault_addr = ADDR_WIDTH'(CHUNK * BB);
            inject_read = 1;
            begin_batch(1, 3);
            wait_drained();
            inject_read = 0;
            begin_batch(1, 0);
            wait_drained();
            write_fault_addr = ADDR_WIDTH'(int'(REGION / 2 + CHUNK * BB));
            inject_write = 1;
            begin_batch(1, 4);
            wait_drained();
            inject_write = 0;
            begin_batch(1, 0);
            wait_drained();
        end
        inject_id = 0;
        begin_batch(20, 6);
        begin : partial_read_reset
            int baseline_reads;
            baseline_reads = observed_r;
            while (observed_r < baseline_reads + 2) begin
                ctrl_tick();
            end
        end
        assert_reset(1);
        release_reset();
        begin_batch(2, 0);
        wait_drained();
        begin_batch(20, 6);
        begin : partial_write_reset
            int baseline_writes;
            baseline_writes = observed_w;
            while (observed_w < baseline_writes + 2) begin
                ctrl_tick();
            end
        end
        assert_reset(0);
        release_reset();
        begin_batch(2, 0);
        wait_drained();
        completion_mask = '0;
        begin_batch(1, 0);
        while (!completion_valid[0]) begin
            ctrl_tick();
        end
        assert_reset(1);
        completion_mask = '1;
        release_reset();
        begin_batch(2, 0);
        wait_drained();
        if (CDC_ENABLE) begin
            begin_batch(12, 6);
            repeat (15) begin
                ctrl_tick();
            end
            ctrl_clock_enable = 0;
            assert_reset(0);
            #(15 * (CTRL_HALF + AXI_HALF));
            axi_reset_request = 1;
            repeat (20) begin
                @(negedge clk);
            end
            if (ctrl_rst_n || completion_valid != '0 || arvalid || awvalid) begin
                $fatal(1, "CDC reset with stopped control clock");
            end
            ctrl_clock_enable = 1;
            wait (rst_n && ctrl_rst_n);
            repeat (10) begin
                ctrl_tick();
            end
            begin_batch(2, 0);
            wait_drained();
            begin_batch(12, 6);
            repeat (15) begin
                ctrl_tick();
            end
            @(negedge clk);
            #0.1;
            axi_clock_enable = 0;
            assert_reset(1);
            #(15 * (CTRL_HALF + AXI_HALF));
            control_reset_request = 1;
            repeat (20) begin
                ctrl_tick();
            end
            if (rst_n || completion_valid != '0) begin
                $fatal(1, "CDC reset with stopped AXI clock");
            end
            axi_clock_enable = 1;
            wait (rst_n && ctrl_rst_n);
            repeat (10) begin
                ctrl_tick();
            end
            begin_batch(2, 0);
            wait_drained();
        end
        if (!axi_clock_enable || !ctrl_clock_enable) begin
            $fatal(1, "multi clock did not recover after reset");
        end
        $display("PASS multi CDC=%0d C=%0d AW=%0d DW=%0d MAX=%0d checks=%0d seed=47C4A11E",
                 CDC_ENABLE, CHANNELS, ADDR_WIDTH, DATA_WIDTH, MAX_BURST_BEATS, checks);
        $finish;
    end
endmodule
`default_nettype wire
