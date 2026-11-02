`default_nettype none
module tb_memory;
    timeunit 1ns / 1ps;

    parameter int unsigned DATA_WIDTH = 128;
    localparam int unsigned ADDR_WIDTH = 32;
    localparam int unsigned ID_WIDTH = 2;
    localparam int unsigned MEM_BYTES = 65536;
    localparam int unsigned BB = DATA_WIDTH / 8;
    logic clk = 0;

    always begin
        #5;
        clk = !clk;
    end
    logic rst_n = 0;
    logic [15:0] cfg_ar_delay = 0;
    logic [15:0] cfg_r_delay = 0;
    logic [15:0] cfg_aw_delay = 0;
    logic [15:0] cfg_w_delay = 0;
    logic [15:0] cfg_b_delay = 0;
    logic [1:0] cfg_r_resp = 0;
    logic [1:0] cfg_b_resp = 0;
    logic cfg_r_bad_id = 0;
    logic cfg_b_bad_id = 0;
    logic [ID_WIDTH-1:0] arid = 2;
    logic [ID_WIDTH-1:0] awid = 1;
    logic [ADDR_WIDTH-1:0] araddr = 0;
    logic [ADDR_WIDTH-1:0] awaddr = 0;
    logic [7:0] arlen = 0;
    logic [7:0] awlen = 0;
    logic [2:0] arsize = 3'($clog2(BB));
    logic [2:0] awsize = 3'($clog2(BB));
    logic [1:0] arburst = 1;
    logic [1:0] awburst = 1;
    logic arvalid = 0;
    logic awvalid = 0;
    logic rready = 0;
    logic wvalid = 0;
    logic wlast = 0;
    logic bready = 0;
    logic [DATA_WIDTH-1:0] wdata = 0;
    logic [BB-1:0] wstrb = 0;
    logic arready;
    logic awready;
    logic rvalid;
    logic rlast;
    logic wready;
    logic bvalid;
    logic [ID_WIDTH-1:0] rid;
    logic [ID_WIDTH-1:0] bid;
    logic [DATA_WIDTH-1:0] rdata;
    logic [1:0] rresp;
    logic [1:0] bresp;
    logic [7:0] expected[MEM_BYTES];
    integer i;
    integer n;
    integer mode;
    logic [DATA_WIDTH-1:0] old_read;
    axi_memory_model #(
        .DATA_WIDTH(DATA_WIDTH),
        .ID_WIDTH(ID_WIDTH)
    ) dut (
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
        .WIDTH(DATA_WIDTH + ID_WIDTH + 3)
    ) r_hold (
        .clk(clk),
        .rst_n(rst_n),
        .valid(rvalid),
        .ready(rready),
        .payload({rdata, rid, rresp, rlast})
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

    task automatic tick();
        @(posedge clk);
        #1;
        @(negedge clk);
    endtask

    task automatic check_memory();
        integer j;
        for (j = 0; j < MEM_BYTES; j = j + 1) begin
            if (dut.mem[j] !== expected[j]) begin
                $fatal(1, "memory model byte %0d got=%h expected=%h", j, dut.mem[j], expected[j]);
            end
        end
    endtask

    task automatic offer_ar(input integer addr, input integer count);
        araddr = ADDR_WIDTH'(addr);
        arlen = 8'(count - 1);
        arvalid = 1;
        #1;
        while (!arready) begin
            tick();
        end
        tick();
        arvalid = 0;
    endtask

    task automatic offer_aw(input integer addr, input integer count);
        awaddr = ADDR_WIDTH'(addr);
        awlen = 8'(count - 1);
        awvalid = 1;
        #1;
        while (!awready) begin
            tick();
        end
        tick();
        awvalid = 0;
    endtask

    task automatic read_burst(input integer addr, input integer count, input integer response,
                              input bit bad_id);
        integer beat;
        integer lane;
        cfg_r_resp = 2'(response);
        cfg_r_bad_id = bad_id;
        offer_ar(addr, count);
        // A later injection setting must not alter this accepted transaction.
        cfg_r_resp = 2'(response ^ 3);
        cfg_r_bad_id = !bad_id;
        for (beat = 0; beat < count; beat = beat + 1) begin
            while (!rvalid) begin
                tick();
            end
            repeat (beat % 4) begin
                tick();
            end
            if (rid !== (arid ^ ID_WIDTH'(bad_id)) || rresp !== 2'(response) ||
                rlast !== (beat == count-1)) begin
                $fatal(1, "memory R fields");
            end
            for (lane = 0; lane < BB; lane = lane + 1) begin
                if (rdata[lane*8+:8] !== expected[addr+beat*BB+lane]) begin
                    $fatal(1, "memory read byte addr=%0d", addr + beat * BB + lane);
                end
            end
            rready = 1;
            tick();
            rready = 0;
        end
    endtask

    task automatic send_w(input integer addr, input integer beat, input integer count,
                          input bit partial);
        integer lane;
        for (lane = 0; lane < BB; lane = lane + 1) begin
            wdata[lane*8+:8] = 8'(addr + beat * 7 + lane + 19);
            wstrb[lane] = !partial || (lane + beat) % 2 == 0;
        end
        wlast = beat == count - 1;
        wvalid = 1;
        #1;
        while (!wready) begin
            tick();
        end
        // Update the independent image for exactly the accepted byte strobes.
        for (lane = 0; lane < BB; lane = lane + 1) begin
            if (wstrb[lane]) begin
                expected[addr+beat*BB+lane] = wdata[lane*8+:8];
            end
        end
        tick();
        wvalid = 0;
    endtask

    task automatic write_burst(input integer addr, input integer count, input integer response,
                               input bit bad_id, input bit partial);
        integer beat;
        cfg_b_resp = 2'(response);
        cfg_b_bad_id = bad_id;
        offer_aw(addr, count);
        cfg_b_resp = 2'(response ^ 3);
        cfg_b_bad_id = !bad_id;
        for (beat = 0; beat < count; beat = beat + 1) begin
            repeat (beat % 3) begin
                tick();
            end
            send_w(addr, beat, count, partial);
        end
        while (!bvalid) begin
            tick();
        end
        repeat (3) begin
            tick();
        end
        if (bid !== (awid ^ ID_WIDTH'(bad_id)) || bresp !== 2'(response)) begin
            $fatal(1, "memory B transaction injection");
        end
        bready = 1;
        tick();
        bready = 0;
    endtask

    task automatic reset_model();
        rst_n = 0;
        #1;
        if (arready || awready || rvalid || wready || bvalid) begin
            $fatal(1, "memory reset suppression");
        end
        tick();
        tick();
        rst_n = 1;
        tick();
        if (rvalid || bvalid || wready) begin
            $fatal(1, "memory reset active transaction");
        end
        check_memory();
    endtask

    initial begin
        #10000000;
        $fatal(1, "memory watchdog");
    end

    initial begin
        for (i = 0; i < MEM_BYTES; i = i + 1) begin
            expected[i] = 8'(i * 13 + 5);
            dut.mem[i] = expected[i];
        end
        @(negedge clk);
        reset_model();
        for (mode = 0; mode < 2; mode = mode + 1) begin
            cfg_ar_delay = 16'(mode * 2);
            cfg_r_delay = 16'(mode);
            cfg_aw_delay = 16'(mode * 3);
            cfg_w_delay = 16'(mode * 2);
            cfg_b_delay = 16'(mode * 4);
            for (n = 1; n <= 256; n = n == 1 ? 3 : n == 3 ? 16 : n == 16 ? 256 : 257) begin
                // Wider data limits a legal AXI burst by the page, not the model count width.
                if (n * BB <= 4096) begin
                    write_burst(32768, n, mode * 2, mode[0], 1);
                    check_memory();
                    read_burst(32768, n, mode * 3, mode[0]);
                end
            end
        end
        fork
            read_burst(0, 4, 2, 1);
            write_burst(32768, 4, 3, 1, 0);
        join
        check_memory();
        // Force R payload creation and a same-address W acceptance onto one edge.
        cfg_ar_delay = 0;
        cfg_aw_delay = 0;
        cfg_r_delay = 0;
        cfg_w_delay = 0;
        cfg_r_resp = 0;
        cfg_b_resp = 0;
        cfg_r_bad_id = 0;
        cfg_b_bad_id = 0;
        araddr = 128;
        awaddr = 128;
        arlen = 0;
        awlen = 0;
        arvalid = 1;
        awvalid = 1;
        tick();
        arvalid = 0;
        awvalid = 0;
        for (i = 0; i < BB; i = i + 1) begin
            old_read[i*8+:8] = expected[128+i];
        end
        send_w(128, 0, 1, 0);
        if (!rvalid || rdata !== old_read) begin
            $fatal(1, "memory read-before-write");
        end
        rready = 1;
        tick();
        rready = 0;
        while (!bvalid) begin
            tick();
        end
        bready = 1;
        tick();
        bready = 0;
        check_memory();
        // Reset cancels a stalled read and a partially accepted write, retaining bytes.
        offer_ar(0, 4);
        offer_aw(32768, 4);
        send_w(32768, 0, 4, 0);
        reset_model();
        read_burst(32768, 4, 0, 0);
        write_burst(32768, 1, 0, 0, 0);
        reset_model();
        $display("PASS independent memory DW=%0d retained writes/strobes/stalls/injection",
                 DATA_WIDTH);
        $finish;
    end

endmodule
`default_nettype wire
