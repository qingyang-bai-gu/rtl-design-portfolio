`default_nettype none
module tb_write;
    timeunit 1ns / 1ps;

    parameter int unsigned ADDR_WIDTH = 32;
    parameter int unsigned DATA_WIDTH = 128;
    parameter int unsigned MAX_BURST_BEATS = 16;
    localparam int unsigned ID_WIDTH = 2;
    localparam int unsigned BEAT_BYTES = DATA_WIDTH / 8;
    localparam int unsigned BURST_LIMIT = MAX_BURST_BEATS < 4096 / BEAT_BYTES ?
                                         MAX_BURST_BEATS : 4096 / BEAT_BYTES;
    logic clk = 0;

    always begin
        #5;
        clk = !clk;
    end
    logic rst_n = 0;
    logic req_valid = 0;
    logic awready = 0;
    logic data_valid = 0;
    logic wready = 0;
    logic bvalid = 0;
    logic result_ready = 0;
    logic [ADDR_WIDTH-1:0] req_addr = 0;
    logic [8:0] req_beats = 0;
    logic [ID_WIDTH-1:0] req_id = 2;
    logic [ID_WIDTH-1:0] bid = 0;
    logic [DATA_WIDTH-1:0] data = 0;
    logic [1:0] bresp = 0;
    logic req_ready;
    logic awvalid;
    logic data_ready;
    logic wvalid;
    logic wlast;
    logic bready;
    logic result_valid;
    logic result_error;
    logic [ADDR_WIDTH-1:0] awaddr;
    logic [7:0] awlen;
    logic [2:0] awsize;
    logic [1:0] awburst;
    logic [ID_WIDTH-1:0] awid;
    logic [DATA_WIDTH-1:0] wdata;
    logic [DATA_WIDTH/8-1:0] wstrb;
    integer aw_count = 0;
    integer w_count = 0;
    integer pop_count = 0;
    integer b_count = 0;
    integer trial;
    integer n;
    integer random_response;
    integer stress_result_stall;
    logic random_bad_id;
    logic random_early_b;
    logic [31:0] rng = 32'h1BADF00D;
    dma_write_engine #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .MAX_BURST_BEATS(MAX_BURST_BEATS),
        .ID_WIDTH(ID_WIDTH)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .req_valid(req_valid),
        .req_ready(req_ready),
        .req_addr(req_addr),
        .req_beats(req_beats),
        .req_id(req_id),
        .awid(awid),
        .awaddr(awaddr),
        .awlen(awlen),
        .awsize(awsize),
        .awburst(awburst),
        .awvalid(awvalid),
        .awready(awready),
        .data(data),
        .data_valid(data_valid),
        .data_ready(data_ready),
        .wdata(wdata),
        .wstrb(wstrb),
        .wlast(wlast),
        .wvalid(wvalid),
        .wready(wready),
        .bid(bid),
        .bresp(bresp),
        .bvalid(bvalid),
        .bready(bready),
        .result_valid(result_valid),
        .result_ready(result_ready),
        .result_error(result_error)
    );
    rv_stability #(
        .WIDTH(ADDR_WIDTH + 15)
    ) aw_hold (
        .clk(clk),
        .rst_n(rst_n),
        .valid(awvalid),
        .ready(awready),
        .payload({awaddr, awid, awlen, awsize, awburst})
    );
    rv_stability #(
        .WIDTH(DATA_WIDTH + DATA_WIDTH / 8 + 1)
    ) w_hold (
        .clk(clk),
        .rst_n(rst_n),
        .valid(wvalid),
        .ready(wready),
        .payload({wdata, wstrb, wlast})
    );
    rv_stability result_hold (
        .clk(clk),
        .rst_n(rst_n),
        .valid(result_valid),
        .ready(result_ready),
        .payload(result_error)
    );

    always @(posedge clk) begin
        if (rst_n) begin
            if (awvalid && awready) begin
                aw_count = aw_count + 1;
            end
            if (wvalid && wready) begin
                w_count = w_count + 1;
            end
            if (data_valid && data_ready) begin
                pop_count = pop_count + 1;
            end
            if (bvalid && bready) begin
                b_count = b_count + 1;
            end
            if ((wvalid && wready) !== (data_valid && data_ready)) begin
                $fatal(1, "write source/W handshake mismatch");
            end
        end

    end

    function automatic int unsigned delay();
        rng = rng ^ (rng << 13);
        rng = rng ^ (rng >> 17);
        rng = rng ^ (rng << 5);
        delay = int'(rng & 3);
    endfunction

    task automatic tick();
        @(posedge clk);
        #1;
        @(negedge clk);
    endtask

    task automatic reset_dma();
        rst_n = 0;
        #1;
        if (req_ready || awvalid || wvalid || bready || data_ready || result_valid) begin
            $fatal(1, "write reset suppression");
        end
        tick();
        tick();
        rst_n = 1;
        tick();
        if (!req_ready) begin
            $fatal(1, "write idle after reset");
        end
    endtask

    task automatic request(input integer count);
        if (count < 0 || count > 511) begin
            $fatal(1, "testbench request does not fit the 9-bit beat-count interface");
        end
        if (!req_ready) begin
            $fatal(1, "write request busy");
        end
        req_beats = 9'(count);
        req_addr = '0;
        req_valid = 1;
        tick();
        req_valid = 0;
    endtask

    task automatic expect_result(input bit expected_error, input int unsigned stall_cycles = 3);
        if (!result_valid || result_error !== expected_error) begin
            $fatal(1, "write result expected=%b got=%b/%b", expected_error, result_valid,
                   result_error);
        end
        repeat (stall_cycles) begin
            if (req_ready || awvalid || wvalid || bready) begin
                $fatal(1, "write extra traffic while result stalled");
            end
            tick();
        end
        result_ready = 1;
        tick();
        result_ready = 0;
        if (!req_ready) begin
            $fatal(1, "write did not return idle");
        end
    endtask

    task automatic send_checked_data(input integer count);
        integer i;
        for (i = 0; i < count; i = i + 1) begin
            repeat (delay()) begin
                tick();
            end
            data = DATA_WIDTH'(i + 197);
            data_valid = 1;
            repeat (delay()) begin
                tick();
            end
            if (bready || result_valid) begin
                $fatal(1, "write accepted early B");
            end
            wready = 1;
            #1;
            if (!wvalid || !data_ready || wdata !== data ||
                wstrb !== {(DATA_WIDTH/8){1'b1}} || wlast !== (i == count-1))
                begin
                $fatal(1, "write payload/last beat=%0d", i);
            end
            tick();
            data_valid = 0;
            wready = 0;
        end
    endtask

    // Self-checking transaction case: verifies address, data accounting, and result.
    // request/tick are mechanical helpers; scenario expectations are explicit arguments.
    task automatic checked_burst(input integer count, input integer response, input bit bad_id,
                                 input bit early_b, input int unsigned result_stalls = 3);
        integer a0;
        integer w0;
        integer p0;
        integer b0;
        a0 = aw_count;
        w0 = w_count;
        p0 = pop_count;
        b0 = b_count;
        bid = bad_id ? 0 : req_id;
        bresp = 2'(response);
        bvalid = early_b;
        request(count);
        repeat (delay() + 1) begin
            tick();
        end
        if (!awvalid || awaddr !== req_addr || awid !== req_id ||
            awlen !== 8'(count-1) || awsize !== 3'($clog2(
                DATA_WIDTH / 8
            )) || awburst != 1) begin
            $fatal(1, "write AW payload");
        end
        if (int'(12'(awaddr)) + count * BEAT_BYTES > 4096) begin
            $fatal(1, "write test stimulus crossed a 4-KiB boundary");
        end
        awready = 1;
        tick();
        awready = 0;
        send_checked_data(count);
        if (!early_b) begin
            repeat (delay() + 1) begin
                if (wvalid || data_ready || result_valid) begin
                    $fatal(1, "extra W before B");
                end
                tick();
            end
            bvalid = 1;
        end
        if (!bready) begin
            $fatal(1, "write not waiting B");
        end
        tick();
        bvalid = 0;
        if (aw_count-a0 != 1 || w_count-w0 != count || pop_count-p0 != count ||
            b_count-b0 != 1) begin
            $fatal(1, "write exact handshake counts");
        end
        expect_result(response != 0 || bad_id, result_stalls);
    endtask

    initial begin
        #10000000;
        $fatal(1, "write watchdog");
    end

    initial begin
        @(negedge clk);
        reset_dma();
        checked_burst(1, 0, 0, 1);
        checked_burst(BURST_LIMIT, 0, 0, 0);
        for (trial = 0; trial < 4; trial = trial + 1) begin
            checked_burst(1, trial, 0, trial[0]);
            checked_burst(1, 0, 0, 0);
        end
        checked_burst(1, 0, 1, 1);
        checked_burst(1, 0, 0, 0);
        request(0);
        expect_result(1);
        request(MAX_BURST_BEATS + 1);
        expect_result(1);
        for (trial = 0; trial < 50; trial = trial + 1) begin
            // Sequence RNG side effects explicitly; argument evaluation order is unspecified.
            n = 1 + delay() % BURST_LIMIT;
            random_response = delay();
            random_bad_id = delay() == 0;
            random_early_b = delay() == 0;
            stress_result_stall = delay();
            checked_burst(n, random_response, random_bad_id, random_early_b, stress_result_stall);
        end
        request(1);
        awready = 1;
        tick();
        awready = 0;
        send_checked_data(1);
        reset_dma();
        request(0);
        reset_dma();
        checked_burst(1, 0, 0, 0);
        request(1);
        reset_dma();
        checked_burst(1, 0, 0, 0);
        $display("PASS write AW=%0d DW=%0d MAX=%0d seed=1BADF00D", ADDR_WIDTH, DATA_WIDTH,
                 MAX_BURST_BEATS);
        $finish;
    end

endmodule
`default_nettype wire
