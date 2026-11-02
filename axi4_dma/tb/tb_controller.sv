`default_nettype none
module tb_controller;
    timeunit 1ns / 1ps;

    parameter int unsigned ADDR_WIDTH = 32;
    parameter int unsigned DATA_WIDTH = 128;
    parameter int unsigned MAX_BURST_BEATS = 16;
    parameter int unsigned TAG_WIDTH = 8;
    localparam int unsigned BB = DATA_WIDTH / 8;
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
    logic [ADDR_WIDTH-1:0] plan_src;
    logic [ADDR_WIDTH-1:0] plan_dst;
    logic [ADDR_WIDTH:0] plan_remaining;
    logic plan_valid = 1;
    logic buffer_empty = 1;
    logic [8:0] plan_beats = 1;
    logic [12:0] plan_bytes = 0;
    logic buffer_flush;
    logic read_req_valid;
    logic read_result_ready;
    logic write_req_valid;
    logic write_result_ready;
    logic [ADDR_WIDTH-1:0] read_req_addr;
    logic [ADDR_WIDTH-1:0] write_req_addr;
    logic [8:0] read_req_beats;
    logic [8:0] write_req_beats;
    logic read_req_ready = 0;
    logic read_result_valid = 0;
    logic read_result_error = 0;
    logic write_req_ready = 0;
    logic write_result_valid = 0;
    logic write_result_error = 0;
    integer reads = 0;
    integer writes = 0;
    integer flushes = 0;
    integer cases = 0;
    logic [ADDR_WIDTH-1:0] far_addr;
    dma_controller #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .MAX_BURST_BEATS(MAX_BURST_BEATS),
        .TAG_WIDTH(TAG_WIDTH)
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
    rv_stability #(
        .WIDTH(ADDR_WIDTH + 9)
    ) read_hold (
        .clk(clk),
        .rst_n(rst_n),
        .valid(read_req_valid),
        .ready(read_req_ready),
        .payload({read_req_addr, read_req_beats})
    );
    rv_stability #(
        .WIDTH(ADDR_WIDTH + 9)
    ) write_hold (
        .clk(clk),
        .rst_n(rst_n),
        .valid(write_req_valid),
        .ready(write_req_ready),
        .payload({write_req_addr, write_req_beats})
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

    always @(posedge clk) begin
        if (rst_n) begin
            if (read_req_valid && read_req_ready) begin
                reads = reads + 1;
            end
            if (write_req_valid && write_req_ready) begin
                writes = writes + 1;
            end
            if (buffer_flush) begin
                flushes = flushes + 1;
            end
        end
    end

    task automatic tick();
        @(posedge clk);
        #1;
        @(negedge clk);
    endtask

    task automatic accept_descriptor(input logic [ADDR_WIDTH-1:0] s, input logic [ADDR_WIDTH-1:0] d,
                                     input logic [ADDR_WIDTH:0] length);
        if (!desc_ready) begin
            $fatal(1, "controller not idle");
        end
        desc_src = s;
        desc_dst = d;
        desc_length = length;
        desc_tag = TAG_WIDTH'(cases);
        cases = cases + 1;
        desc_valid = 1;
        tick();
        desc_valid = 0;
        // Upstream payload may change after acceptance.
        desc_src = '1;
        desc_dst = '1;
        desc_length = 0;
    endtask

    task automatic finish_case(input logic [1:0] status);
        while (!completion_valid) begin
            tick();
        end
        if (completion_status !== status || completion_tag !== TAG_WIDTH'(cases - 1)) begin
            $fatal(1, "controller completion status/tag");
        end
        repeat (3) begin
            if (desc_ready || read_req_valid || write_req_valid) begin
                $fatal(1, "controller extra traffic while complete");
            end
            tick();
        end
        completion_ready = 1;
        tick();
        completion_ready = 0;
        if (!desc_ready) begin
            $fatal(1, "controller completion not consumed");
        end
    endtask

    task automatic invalid(input logic [ADDR_WIDTH-1:0] s, input logic [ADDR_WIDTH-1:0] d,
                           input logic [ADDR_WIDTH:0] length);
        integer r0;
        integer w0;
        r0 = reads;
        w0 = writes;
        accept_descriptor(s, d, length);
        finish_case(1);
        if (reads != r0 || writes != w0) begin
            $fatal(1, "invalid descriptor made traffic");
        end
    endtask

    task automatic transfer(input logic [ADDR_WIDTH-1:0] source,
                            input logic [ADDR_WIDTH-1:0] destination, input integer length,
                            input integer fault);
        logic [ADDR_WIDTH-1:0] s;
        logic [ADDR_WIDTH-1:0] d;
        integer left;
        integer n;
        integer f0;
        s = source;
        d = destination;
        left = length;
        f0 = flushes;
        buffer_empty = 0;
        accept_descriptor(s, d, (ADDR_WIDTH + 1)'(length));
        repeat (3) begin
            if (read_req_valid || write_req_valid) begin
                $fatal(1, "buffer empty gating");
            end
            tick();
        end
        buffer_empty = 1;
        while (left > 0) begin
            if (plan_src !== s || plan_dst !== d || plan_remaining !== (ADDR_WIDTH+1)'(left)) begin
                $fatal(1, "controller planner-state interface");
            end
            n = left / BB;
            if (n > MAX_BURST_BEATS) begin
                n = MAX_BURST_BEATS;
            end
            if (n > (4096 - int'(12'(s))) / BB) begin
                n = (4096 - int'(12'(s))) / BB;
            end
            if (n > (4096 - int'(12'(d))) / BB) begin
                n = (4096 - int'(12'(d))) / BB;
            end
            plan_beats = 9'(n);
            plan_bytes = 13'(n * BB);
            while (!read_req_valid) begin
                tick();
            end
            if (read_req_addr !== s || read_req_beats !== 9'(n)) begin
                $fatal(1, "controller read plan");
            end
            repeat (2) begin
                tick();
            end
            read_req_ready = 1;
            tick();
            read_req_ready = 0;
            repeat (2) begin
                if (write_req_valid || completion_valid) begin
                    $fatal(1, "early write/complete");
                end
                tick();
            end
            if (!read_result_ready) begin
                $fatal(1, "controller did not wait for read result");
            end
            read_result_error = fault == 2;
            read_result_valid = 1;
            tick();
            read_result_valid = 0;
            if (fault == 2) begin
                if (!buffer_flush || write_req_valid) begin
                    $fatal(1, "read error flush");
                end
                tick();
                finish_case(2);
                if (flushes - f0 != 1) begin
                    $fatal(1, "flush count");
                end
                left = 0;
            end else begin
                while (!write_req_valid) begin
                    tick();
                end
                if (write_req_addr !== d || write_req_beats !== 9'(n)) begin
                    $fatal(1, "controller write plan");
                end
                repeat (2) begin
                    tick();
                end
                write_req_ready = 1;
                tick();
                write_req_ready = 0;
                repeat (2) begin
                    if (completion_valid) begin
                        $fatal(1, "early completion before write result");
                    end
                    tick();
                end
                if (!write_result_ready) begin
                    $fatal(1, "controller did not wait for write result");
                end
                write_result_valid = 1;
                write_result_error = fault == 3;
                tick();
                write_result_valid = 0;
                if (fault == 3) begin
                    finish_case(3);
                    left = 0;
                end else begin
                    s = s + ADDR_WIDTH'(n * BB);
                    d = d + ADDR_WIDTH'(n * BB);
                    left = left - n * BB;
                    if (left == 0) begin
                        finish_case(0);
                    end
                end
            end
        end
    endtask

    initial begin
        #10000000;
        $fatal(1, "controller watchdog");
    end

    initial begin
        @(negedge clk);
        tick();
        rst_n = 1;
        tick();
        far_addr = ADDR_WIDTH'(1) << (ADDR_WIDTH - 1);
        transfer(0, far_addr, BB, 0);
        transfer(0, far_addr, BB * (MAX_BURST_BEATS + 3), 0);
        transfer(0, far_addr, BB * 3, 2);
        transfer(0, far_addr, BB, 0);
        transfer(0, far_addr, BB * 3, 3);
        transfer(0, far_addr, BB, 0);
        invalid(0, far_addr, 0);
        invalid(0, 0, (ADDR_WIDTH + 1)'(BB));
        invalid(0, ADDR_WIDTH'(BB), (ADDR_WIDTH + 1)'(2 * BB));
        invalid('1 - ADDR_WIDTH'(BB - 1), 0, (ADDR_WIDTH + 1)'(2 * BB));
        invalid(0, '1 - ADDR_WIDTH'(BB - 1), (ADDR_WIDTH + 1)'(2 * BB));
        invalid(0, far_addr, (ADDR_WIDTH + 1)'(1) << ADDR_WIDTH);
        if (BB > 1) begin
            invalid(1, far_addr, (ADDR_WIDTH + 1)'(BB));
            invalid(0, far_addr + 1'b1, (ADDR_WIDTH + 1)'(BB));
            invalid(0, far_addr, (ADDR_WIDTH + 1)'(BB + 1));
        end
        transfer(0, '1 - ADDR_WIDTH'(BB - 1), BB, 0);
        // A legal descriptor with an unavailable plan must never issue an engine request.
        plan_valid = 0;
        accept_descriptor(0, far_addr, (ADDR_WIDTH + 1)'(BB));
        finish_case(1);
        plan_valid = 1;
        // Adjacent half-open intervals are legal.
        transfer(0, ADDR_WIDTH'(BB), BB, 0);
        $display("PASS controller AW=%0d DW=%0d MAX=%0d cases=%0d", ADDR_WIDTH, DATA_WIDTH,
                 MAX_BURST_BEATS, cases);
        $finish;
    end

endmodule
`default_nettype wire
