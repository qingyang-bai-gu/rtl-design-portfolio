`default_nettype none
module tb_system;
    timeunit 1ns / 1ps;

    parameter int unsigned ADDR_WIDTH = 32;
    parameter int unsigned DATA_WIDTH = 128;
    parameter int unsigned MAX_BURST_BEATS = 16;
    parameter int unsigned BUFFER_DEPTH = MAX_BURST_BEATS;
    localparam int unsigned TAG_WIDTH = 8;
    localparam int unsigned ID_WIDTH = 1;
    localparam int unsigned BB = DATA_WIDTH / 8;
    localparam logic [2:0] AXI_SIZE = 3'($clog2(BB));
    localparam int unsigned MEM_BYTES = ADDR_WIDTH == 12 ? 4096 : 65536;
    localparam int unsigned DEST = MEM_BYTES / 2;
    localparam int unsigned CHUNK = MAX_BURST_BEATS < 4096 / BB ? MAX_BURST_BEATS : 4096 / BB;
    logic clk = 0;

    always begin
        #5;
        clk = !clk;
    end
    logic rst_n = 0;
    logic desc_valid = 0;
    logic completion_ready = 0;
    logic [ADDR_WIDTH-1:0] desc_src = 0;
    logic [ADDR_WIDTH-1:0] desc_dst = 0;
    logic [ADDR_WIDTH:0] desc_length = 0;
    logic [TAG_WIDTH-1:0] desc_tag = 0;
    logic desc_ready;
    logic completion_valid;
    logic [TAG_WIDTH-1:0] completion_tag;
    logic [1:0] completion_status;
    logic [ID_WIDTH-1:0] arid;
    logic [ID_WIDTH-1:0] rid;
    logic [ID_WIDTH-1:0] awid;
    logic [ID_WIDTH-1:0] bid;
    logic [ADDR_WIDTH-1:0] araddr;
    logic [ADDR_WIDTH-1:0] awaddr;
    logic [7:0] arlen;
    logic [7:0] awlen;
    logic [2:0] arsize;
    logic [2:0] awsize;
    logic [2:0] arprot;
    logic [2:0] awprot;
    logic [1:0] arburst;
    logic [1:0] awburst;
    logic [1:0] rresp;
    logic [1:0] bresp;
    logic arlock;
    logic awlock;
    logic [3:0] arcache;
    logic [3:0] arqos;
    logic [3:0] arregion;
    logic [3:0] awcache;
    logic [3:0] awqos;
    logic [3:0] awregion;
    logic arvalid;
    logic arready;
    logic rvalid;
    logic rready;
    logic rlast;
    logic awvalid;
    logic awready;
    logic wvalid;
    logic wready;
    logic wlast;
    logic bvalid;
    logic bready;
    logic [DATA_WIDTH-1:0] rdata;
    logic [DATA_WIDTH-1:0] wdata;
    logic [BB-1:0] wstrb;
    logic [15:0] cfg_ar_delay = 2;
    logic [15:0] cfg_r_delay = 1;
    logic [15:0] cfg_aw_delay = 2;
    logic [15:0] cfg_w_delay = 1;
    logic [15:0] cfg_b_delay = 3;
    logic active = 0;
    logic inject_id = 0;
    integer fault_r = -1;
    integer fault_w = -1;
    integer ar_seen = 0;
    integer r_seen = 0;
    integer aw_seen = 0;
    integer w_seen = 0;
    integer b_seen = 0;
    integer c_seen = 0;
    logic [1:0] cfg_r_resp;
    assign cfg_r_resp = active && ar_seen == fault_r && !inject_id ? 2 : 0;
    logic [1:0] cfg_b_resp;
    assign cfg_b_resp = active && aw_seen == fault_w && !inject_id ? 3 : 0;
    logic cfg_r_bad_id;
    assign cfg_r_bad_id = active && ar_seen == fault_r && inject_id;
    logic cfg_b_bad_id;
    assign cfg_b_bad_id = active && aw_seen == fault_w && inject_id;
    logic [7:0] expected[MEM_BYTES];
    integer burst_src[1024];
    integer burst_dst[1024];
    integer burst_count[1024];
    integer chunks = 0;
    integer phase = 0;
    integer read_beat = 0;
    integer write_beat = 0;
    integer case_number = 0;
    integer i;
    integer trial;
    integer s;
    integer d;
    integer n;
    integer reset_beats;
    logic [31:0] rng = 32'hDA4A2026;
    axi_dma #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .MAX_BURST_BEATS(MAX_BURST_BEATS),
        .BUFFER_DEPTH(BUFFER_DEPTH)
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
        .bready(bready)
    );
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
        .WIDTH(DATA_WIDTH + BB + 1)
    ) w_hold (
        .clk(clk),
        .rst_n(rst_n),
        .valid(wvalid),
        .ready(wready),
        .payload({wdata, wstrb, wlast})
    );
    rv_stability #(
        .WIDTH(DATA_WIDTH + 4)
    ) r_hold (
        .clk(clk),
        .rst_n(rst_n),
        .valid(rvalid),
        .ready(rready),
        .payload({rdata, rid, rresp, rlast})
    );
    rv_stability #(
        .WIDTH(3)
    ) b_hold (
        .clk(clk),
        .rst_n(rst_n),
        .valid(bvalid),
        .ready(bready),
        .payload({bid, bresp})
    );
    rv_stability #(
        .WIDTH(TAG_WIDTH + 2)
    ) completion_hold (
        .clk(clk),
        .rst_n(rst_n),
        .valid(completion_valid),
        .ready(completion_ready),
        .payload({completion_tag, completion_status})
    );
    rv_stability #(
        .WIDTH(3 * ADDR_WIDTH + 1 + TAG_WIDTH)
    ) desc_hold (
        .clk(clk),
        .rst_n(rst_n),
        .valid(desc_valid),
        .ready(desc_ready),
        .payload({desc_src, desc_dst, desc_length, desc_tag})
    );
    // Scoreboard observes only interfaces. All addresses/lengths come from a byte-room oracle.

    always @(posedge clk) begin
        if (rst_n && active) begin : scoreboard
            integer lane;
            integer source_byte;
            integer destination_byte;
            if (arvalid && arready) begin
                if (phase != 0 || ar_seen >= chunks || araddr !== ADDR_WIDTH'(burst_src[ar_seen]) ||
                arlen !== 8'(burst_count[ar_seen]-1)) begin
                    $fatal(1, "system case=%0d AR oracle/sequence idx=%0d addr=%h len=%0d",
                           case_number, ar_seen, araddr, arlen);
                end
                if (arid != '0 || arburst != 2'b01 || arsize != AXI_SIZE ||
                    {arlock, arcache, arprot, arqos, arregion} != '0) begin
                    $fatal(1, "system AR attributes");
                end
                ar_seen = ar_seen + 1;
                phase = 1;
                read_beat = 0;
            end
            if (rvalid && rready) begin
                if (phase != 1 || rlast !== (read_beat == burst_count[ar_seen-1] - 1)) begin
                    $fatal(1, "system R sequence/count");
                end
                read_beat = read_beat + 1;
                r_seen = r_seen + 1;
                if (read_beat == burst_count[ar_seen-1]) begin
                    phase = 2;
                end
            end
            if (awvalid && awready) begin
                if (phase != 2 || aw_seen >= chunks || aw_seen != ar_seen-1 ||
                awaddr !== ADDR_WIDTH'(burst_dst[aw_seen]) ||
                awlen !== 8'(burst_count[aw_seen]-1)) begin
                    $fatal(1, "system AW oracle/sequence idx=%0d addr=%h len=%0d", aw_seen, awaddr,
                           awlen);
                end
                if (awid != '0 || awburst != 2'b01 || awsize != AXI_SIZE ||
                    {awlock, awcache, awprot, awqos, awregion} != '0) begin
                    $fatal(1, "system AW attributes");
                end
                aw_seen = aw_seen + 1;
                phase = 3;
                write_beat = 0;
            end
            if (wvalid && wready) begin
                if (phase != 3 || wlast !== (write_beat == burst_count[aw_seen-1]-1) ||
                wstrb !== {BB{1'b1}}) begin
                    $fatal(1, "system W sequence/strobes/last");
                end
                for (lane = 0; lane < BB; lane = lane + 1) begin
                    source_byte = burst_src[aw_seen-1] + write_beat * BB + lane;
                    destination_byte = burst_dst[aw_seen-1] + write_beat * BB + lane;
                    if (wdata[lane*8+:8] !== expected[source_byte]) begin
                        $fatal(1, "system data byte src=%0d dst=%0d got=%h expected=%h",
                               source_byte, destination_byte, wdata[lane*8+:8],
                               expected[source_byte]);
                    end
                    expected[destination_byte] = expected[source_byte];
                end
                write_beat = write_beat + 1;
                w_seen = w_seen + 1;
                if (write_beat == burst_count[aw_seen-1]) begin
                    phase = 4;
                end
            end
            if (bvalid && bready) begin
                if (phase != 4) begin
                    $fatal(1, "system B before accepted WLAST");
                end
                b_seen = b_seen + 1;
                phase = 0;
            end
            if (completion_valid && completion_ready) begin
                c_seen = c_seen + 1;
            end
        end

    end

    function automatic logic [31:0] random_word();
        rng = rng ^ (rng << 13);
        rng = rng ^ (rng >> 17);
        rng = rng ^ (rng << 5);
        random_word = rng;
    endfunction

    task automatic tick();
        @(posedge clk);
        #1;
        @(negedge clk);
    endtask

    task automatic check_memory();
        integer byte_index;
        for (byte_index = 0; byte_index < MEM_BYTES; byte_index = byte_index + 1) begin
            if (memory.mem[byte_index] !== expected[byte_index]) begin
                $fatal(1, "system case=%0d whole-memory byte=%0d got=%h expected=%h", case_number,
                       byte_index, memory.mem[byte_index], expected[byte_index]);
            end
        end
    endtask

    task automatic prepare(input integer source, input integer destination, input integer length,
                           input bit valid_desc);
        integer ss;
        integer dd;
        integer left;
        integer bytes;
        if (!desc_ready) begin
            $fatal(1, "system descriptor not ready");
        end
        active = 1;
        case_number = case_number + 1;
        ar_seen = 0;
        r_seen = 0;
        aw_seen = 0;
        w_seen = 0;
        b_seen = 0;
        c_seen = 0;
        phase = 0;
        chunks = 0;
        ss = source;
        dd = destination;
        left = length;
        if (valid_desc) begin
            while (left > 0) begin
                bytes = left;
                if (bytes > MAX_BURST_BEATS * BB) begin
                    bytes = MAX_BURST_BEATS * BB;
                end
                if (bytes > 4096 - ss % 4096) begin
                    bytes = 4096 - ss % 4096;
                end
                if (bytes > 4096 - dd % 4096) begin
                    bytes = 4096 - dd % 4096;
                end
                burst_src[chunks] = ss;
                burst_dst[chunks] = dd;
                burst_count[chunks] = bytes / BB;
                chunks = chunks + 1;
                ss = ss + bytes;
                dd = dd + bytes;
                left = left - bytes;
            end
        end
        desc_src = ADDR_WIDTH'(source);
        desc_dst = ADDR_WIDTH'(destination);
        desc_length = (ADDR_WIDTH + 1)'(length);
        desc_tag = TAG_WIDTH'(case_number);
        desc_valid = 1;
        tick();
        desc_valid = 0;
    endtask

    task automatic finish_case(input integer status, input integer stall);
        integer expected_ar;
        integer expected_aw;
        integer expected_r;
        integer expected_w;
        integer k;
        while (!completion_valid) begin
            tick();
        end
        if (completion_tag !== TAG_WIDTH'(case_number) || completion_status !== 2'(status)) begin
            $fatal(1, "system case=%0d completion got=%d tag=%h expected=%0d", case_number,
                   completion_status, completion_tag, status);
        end
        expected_ar = status == 1 ? 0 : status == 2 ? fault_r+1 :
            status == 3 ? fault_w+1 : chunks;
        expected_aw = status == 2 ? fault_r : expected_ar;
        expected_r = 0;
        expected_w = 0;
        for (k = 0; k < expected_ar; k = k + 1) begin
            expected_r = expected_r + burst_count[k];
        end
        for (k = 0; k < expected_aw; k = k + 1) begin
            expected_w = expected_w + burst_count[k];
        end
        if (ar_seen != expected_ar || aw_seen != expected_aw || r_seen != expected_r ||
            w_seen != expected_w || b_seen != expected_aw || c_seen != 0)
            begin
            $fatal(1, "system exact counts AR/R/AW/W/B=%0d/%0d/%0d/%0d/%0d", ar_seen, r_seen,
                   aw_seen, w_seen, b_seen);
        end
        repeat (stall) begin
            tick();
        end
        completion_ready = 1;
        tick();
        completion_ready = 0;
        if (c_seen != 1 || !desc_ready) begin
            $fatal(1, "system completion acceptance");
        end
        repeat (2) begin
            if (completion_valid || arvalid || awvalid || wvalid) begin
                $fatal(1, "system duplicate completion/traffic");
            end
            tick();
        end
        check_memory();
        active = 0;
        fault_r = -1;
        fault_w = -1;
    endtask

    task automatic copy_case(input integer source, input integer destination, input integer length,
                             input integer stall);
        fault_r = -1;
        fault_w = -1;
        inject_id = 0;
        prepare(source, destination, length, 1);
        finish_case(0, stall);
    endtask

    task automatic cancel_reset();
        active = 0;
        rst_n = 0;
        #1;
        if (desc_ready || completion_valid || arvalid || rready || awvalid || wvalid || bready)
            begin
            $fatal(1, "system reset handshake suppression");
        end
        tick();
        tick();
        rst_n = 1;
        repeat (5) begin
            tick();
            if (completion_valid) begin
                $fatal(1, "completion for canceled descriptor");
            end
        end
        if (!desc_ready) begin
            $fatal(1, "system reset idle recovery");
        end
        check_memory();
    endtask

    initial begin
        #100000000;
        $fatal(1, "system watchdog case=%0d", case_number);
    end

    initial begin
        for (i = 0; i < MEM_BYTES; i = i + 1) begin
            expected[i] = 8'((i * 29) ^ (i >> 8) ^ ((i >> 12) * 7));
            memory.mem[i] = expected[i];
        end
        @(negedge clk);
        cancel_reset();
        copy_case(0, DEST, BB, 0);
        copy_case(0, DEST, CHUNK * BB, 1);
        copy_case(0, DEST, (CHUNK + 3) * BB, 2);
        if (ADDR_WIDTH > 12) begin
            copy_case(4096 - BB, 12288 - 2 * BB, BB * 6, 3);
        end
        copy_case(0, DEST, BB * 64, 3);
        if (DATA_WIDTH == 128 && MAX_BURST_BEATS == 16 && ar_seen != 4) begin
            $fatal(1, "64 beats must be exactly four bursts");
        end
        for (trial = 0; trial < 32; trial = trial + 1) begin
            if (trial % 3 == 0) begin
                cfg_ar_delay = 0;
                cfg_r_delay = 0;
                cfg_aw_delay = 0;
                cfg_w_delay = 0;
                cfg_b_delay = 0;
            end else if (trial % 3 == 1) begin
                cfg_ar_delay = 3;
                cfg_r_delay = 1;
                cfg_aw_delay = 0;
                cfg_w_delay = 2;
                cfg_b_delay = 5;
            end else begin
                cfg_ar_delay = 1;
                cfg_r_delay = 3;
                cfg_aw_delay = 4;
                cfg_w_delay = 0;
                cfg_b_delay = 1;
            end
            rng = random_word();
            s = int'(rng & 32'h7FFFFFFF) % (MEM_BYTES / 8 / BB) * BB;
            rng = random_word();
            d = DEST + int'(rng & 32'h7FFFFFFF) % (MEM_BYTES / 8 / BB) * BB;
            rng = random_word();
            n = 1 + int'(rng & 32'h7FFFFFFF) % 64;
            copy_case(s, d, n * BB, trial % 4);
        end
        for (trial = 0; trial < 2; trial = trial + 1) begin
            inject_id = trial[0];
            fault_r = 1;
            prepare(0, DEST, CHUNK * BB * 3, 1);
            finish_case(2, 3);
            copy_case(0, DEST, BB * 3, 1);
            inject_id = trial[0];
            fault_w = 1;
            prepare(0, DEST, CHUNK * BB * 3, 1);
            finish_case(3, 2);
            copy_case(0, DEST, BB * 3, 0);
        end
        prepare(0, DEST, 0, 0);
        finish_case(1, 3);
        copy_case(0, DEST, BB, 0);
        prepare(0, 0, BB, 0);
        finish_case(1, 2);
        copy_case(0, DEST, BB, 0);
        if (BB > 1) begin
            prepare(1, DEST, BB, 0);
            finish_case(1, 1);
            copy_case(0, DEST, BB, 0);
        end
        reset_beats = CHUNK < 8 ? CHUNK : 8;
        cfg_r_delay = 3;
        cfg_w_delay = 3;
        prepare(0, DEST, BB * reset_beats, 1);
        if (reset_beats > 1) begin
            while (r_seen < 2) begin
                tick();
            end
        end else begin
            while (ar_seen < 1) begin
                tick();
            end
        end
        if (aw_seen != 0) begin
            $fatal(1, "reset-read test reached a write");
        end
        cancel_reset();
        copy_case(0, DEST, BB * 3, 0);
        prepare(0, DEST, BB * reset_beats, 1);
        while (w_seen < (reset_beats > 1 ? 2 : 1)) begin
            tick();
        end
        cancel_reset();
        copy_case(0, DEST, BB * 3, 0);
        prepare(0, DEST, BB, 1);
        while (!completion_valid) begin
            tick();
        end
        cancel_reset();
        copy_case(0, DEST, BB * 3, 0);
        $display("PASS system AW=%0d DW=%0d MAX=%0d cases=%0d seed=DA4A2026", ADDR_WIDTH,
                 DATA_WIDTH, MAX_BURST_BEATS, case_number);
        $finish;
    end

endmodule
`default_nettype wire
