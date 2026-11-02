`default_nettype none
module tb_read;
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
    logic arready = 0;
    logic rvalid = 0;
    logic rlast = 0;
    logic data_ready = 0;
    logic result_ready = 0;
    logic [ADDR_WIDTH-1:0] req_addr = 0;
    logic [8:0] req_beats = 0;
    logic [ID_WIDTH-1:0] req_id = 2;
    logic [ID_WIDTH-1:0] rid = 0;
    logic [DATA_WIDTH-1:0] rdata = 0;
    logic [1:0] rresp = 0;
    logic req_ready;
    logic arvalid;
    logic rready;
    logic data_valid;
    logic result_valid;
    logic result_error;
    logic [ADDR_WIDTH-1:0] araddr;
    logic [7:0] arlen;
    logic [2:0] arsize;
    logic [1:0] arburst;
    logic [ID_WIDTH-1:0] arid;
    logic [DATA_WIDTH-1:0] data;
    integer ar_count = 0;
    integer r_count = 0;
    integer data_count = 0;
    integer results = 0;
    integer trial;
    integer n;
    integer stress_result_stall;
    logic [31:0] rng = 32'h1BADF00D;
    dma_read_engine #(
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
        .data(data),
        .data_valid(data_valid),
        .data_ready(data_ready),
        .result_valid(result_valid),
        .result_ready(result_ready),
        .result_error(result_error)
    );
    rv_stability #(
        .WIDTH(ADDR_WIDTH + 15)
    ) ar_hold (
        .clk(clk),
        .rst_n(rst_n),
        .valid(arvalid),
        .ready(arready),
        .payload({araddr, arid, arlen, arsize, arburst})
    );
    rv_stability #(
        .WIDTH(DATA_WIDTH)
    ) data_hold (
        .clk(clk),
        .rst_n(rst_n),
        .valid(data_valid),
        .ready(data_ready),
        .payload(data)
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
            if (arvalid && arready) begin
                ar_count = ar_count + 1;
            end
            if (rvalid && rready) begin
                r_count = r_count + 1;
            end
            if (data_valid && data_ready) begin
                data_count = data_count + 1;
            end
            if (result_valid && result_ready) begin
                results = results + 1;
            end
        end

    end

    function automatic int unsigned random_delay();
        rng = rng ^ (rng << 13);
        rng = rng ^ (rng >> 17);
        rng = rng ^ (rng << 5);
        random_delay = int'(rng & 3);
    endfunction

    task automatic tick();
        @(posedge clk);
        #1;
        @(negedge clk);
    endtask

    task automatic reset_dma();
        rst_n = 0;
        #1;
        if (req_ready || arvalid || rready || data_valid || result_valid) begin
            $fatal(1, "read reset suppression");
        end
        tick();
        tick();
        rst_n = 1;
        tick();
        if (!req_ready) begin
            $fatal(1, "read idle after reset");
        end
    endtask

    task automatic request(input integer count);
        if (count < 0 || count > 511) begin
            $fatal(1, "testbench request does not fit the 9-bit beat-count interface");
        end
        if (!req_ready) begin
            $fatal(1, "read request busy");
        end
        req_beats = 9'(count);
        req_addr = '0;
        req_valid = 1;
        tick();
        req_valid = 0;
    endtask

    task automatic expect_result(input bit expected_error, input int unsigned stall_cycles = 3);
        if (!result_valid || result_error !== expected_error) begin
            $fatal(1, "read result expected=%b got=%b/%b", expected_error, result_valid,
                   result_error);
        end
        repeat (stall_cycles) begin
            if (req_ready || arvalid || rready) begin
                $fatal(1, "read extra traffic");
            end
            tick();
        end
        result_ready = 1;
        tick();
        result_ready = 0;
        if (!req_ready) begin
            $fatal(1, "read did not release request");
        end
    endtask
    // fault: 1 early RLAST, 2 missing final, 3 response error, 4 wrong ID.

    // Self-checking transaction case: verifies address, data accounting, and result.
    // request/tick are mechanical helpers; scenario expectations are explicit arguments.
    task automatic checked_burst(input integer count, input integer fault,
                                 input int unsigned result_stalls = 3);
        integer a0;
        integer r0;
        integer d0;
        integer i;
        integer stalls;
        a0 = ar_count;
        r0 = r_count;
        d0 = data_count;
        request(count);
        repeat (3) begin
            tick();
        end
        if (!arvalid || araddr !== req_addr || arid !== req_id ||
            arlen !== 8'(count-1) || arsize !== 3'($clog2(
                DATA_WIDTH / 8
            )) || arburst != 1) begin
            $fatal(1, "read AR payload");
        end
        if (int'(12'(araddr)) + count * BEAT_BYTES > 4096) begin
            $fatal(1, "read test stimulus crossed a 4-KiB boundary");
        end
        arready = 1;
        tick();
        arready = 0;
        // Invalid R payload must have no effect without an R handshake.
        rid = 0;
        rresp = 3;
        rlast = 1;
        data_ready = 1;
        repeat (2) begin
            tick();
        end
        data_ready = 0;
        for (i = 0; i < count; i = i + 1) begin
            repeat (random_delay()) begin
                tick();
            end
            rdata = DATA_WIDTH'(i + 97);
            rid = req_id;
            rresp = 0;
            rlast = i == count - 1;
            if (fault == 1 && i == 0) begin
                rlast = 1;
            end
            if (fault == 2 && i == count - 1) begin
                rlast = 0;
            end
            if (fault == 3 && i == 0) begin
                rresp = 2;
            end
            if (fault == 5 && i == 0) begin
                rresp = 1;
            end
            if (fault == 6 && i == 0) begin
                rresp = 3;
            end
            if (fault == 4 && i == 0) begin
                rid = 0;
            end
            rvalid = 1;
            data_ready = 0;
            stalls = random_delay();
            repeat (stalls) begin
                tick();
            end
            if (result_valid) begin
                $fatal(1, "read result before accepted final beat");
            end
            data_ready = 1;
            #1;
            if (!rready || !data_valid || data !== rdata) begin
                $fatal(1, "read stream forwarding");
            end
            tick();
            rvalid = 0;
            data_ready = 0;
        end
        if (ar_count - a0 != 1 || r_count - r0 != count || data_count - d0 != count) begin
            $fatal(1, "read handshake counts");
        end
        expect_result(fault != 0, result_stalls);
    endtask

    initial begin
        #10000000;
        $fatal(1, "read watchdog");
    end

    initial begin
        @(negedge clk);
        reset_dma();
        checked_burst(1, 0);
        checked_burst(BURST_LIMIT, 0);
        for (trial = 1; trial <= 6; trial = trial + 1) begin
            n = MAX_BURST_BEATS < 3 ? MAX_BURST_BEATS : 3;
            if (trial != 1 || n > 1) begin
                checked_burst(n, trial);
            end
            checked_burst(1, 0);
        end
        request(0);
        expect_result(1);
        request(MAX_BURST_BEATS + 1);
        expect_result(1);
        for (trial = 0; trial < 20; trial = trial + 1) begin
            n = 1 + random_delay() % BURST_LIMIT;
            stress_result_stall = random_delay();
            checked_burst(n, trial % 3 == 0 ? 3 : 0, stress_result_stall);
        end
        request(1);
        reset_dma();
        request(1);
        arready = 1;
        tick();
        arready = 0;
        reset_dma();
        request(0);
        reset_dma();
        checked_burst(1, 0);
        $display("PASS read AW=%0d DW=%0d MAX=%0d seed=1BADF00D results=%0d", ADDR_WIDTH,
                 DATA_WIDTH, MAX_BURST_BEATS, results);
        $finish;
    end

endmodule
`default_nettype wire
