`default_nettype none
module tb_buffer;
    timeunit 1ns / 1ps;

    parameter int unsigned DATA_WIDTH = 128;
    parameter int unsigned DEPTH = 3;
    localparam int unsigned COUNT_WIDTH = DEPTH <= 1 ? 1 : $clog2(64'(DEPTH) + 64'd1);
    logic clk = 0;

    always begin
        #5;
        clk = !clk;
    end
    logic rst_n = 0;
    logic flush = 0;
    logic push_valid = 0;
    logic pop_ready = 0;
    logic [DATA_WIDTH-1:0] push_data = 0;
    logic push_ready;
    logic pop_valid;
    logic empty;
    logic full;
    logic [DATA_WIDTH-1:0] pop_data;
    logic [COUNT_WIDTH-1:0] occupancy;
    logic [DATA_WIDTH-1:0] queue[20001];
    integer head = 0;
    integer tail = 0;
    integer size = 0;
    integer i;
    integer j;
    logic [31:0] rng = 32'hB00FCAFE;
    dma_burst_buffer #(
        .DATA_WIDTH(DATA_WIDTH),
        .DEPTH(DEPTH)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .flush(flush),
        .push_data(push_data),
        .push_valid(push_valid),
        .push_ready(push_ready),
        .pop_data(pop_data),
        .pop_valid(pop_valid),
        .pop_ready(pop_ready),
        .occupancy(occupancy),
        .empty(empty),
        .full(full)
    );
    // Manual stimulus can withdraw offers; the FIFO output must still hold.
    rv_stability #(
        .WIDTH(DATA_WIDTH)
    ) hold (
        .clk(clk),
        .rst_n(rst_n && !flush),
        .valid(pop_valid),
        .ready(pop_ready),
        .payload(pop_data)
    );

    function automatic logic [31:0] random_word();
        rng = rng ^ (rng << 13);
        rng = rng ^ (rng >> 17);
        rng = rng ^ (rng << 5);
        random_word = rng;
    endfunction

    task automatic cycle(input bit push, input bit pop, input bit clear,
                         input logic [DATA_WIDTH-1:0] value);
        bit accepted_push, accepted_pop;
        push_valid = push;
        pop_ready = pop;
        flush = clear;
        push_data = value;
        #1;
        if (push_ready !== (!clear && size < DEPTH) ||
            pop_valid !== (!clear && size > 0) || occupancy !== COUNT_WIDTH'(size) ||
            empty !== (size == 0) || full !== (size == DEPTH))
            begin
            $fatal(1, "buffer flags/occupancy depth=%0d size=%0d", DEPTH, size);
        end
        if (!clear && size > 0 && pop_data !== queue[head]) begin
            $fatal(1, "buffer show-ahead got=%h expected=%h", pop_data, queue[head]);
        end
        accepted_push = push && push_ready;
        accepted_pop = pop && pop_valid;
        @(posedge clk);
        if (clear) begin
            size = 0;
            head = 0;
            tail = 0;
        end else begin
            if (accepted_pop) begin
                head = head + 1;
                size = size - 1;
            end
            if (accepted_push) begin
                queue[tail] = value;
                tail = tail + 1;
                size = size + 1;
            end
        end
        #1;
        if (occupancy !== COUNT_WIDTH'(size)) begin
            $fatal(1, "buffer next occupancy");
        end
        @(negedge clk);
    endtask

    task automatic reset_dma();
        rst_n = 0;
        flush = 1;
        push_valid = 1;
        pop_ready = 1;
        #1;
        if (push_ready || pop_valid) begin
            $fatal(1, "buffer reset suppression");
        end
        @(posedge clk);
        #1;
        if (occupancy != 0) begin
            $fatal(1, "buffer reset state");
        end
        @(negedge clk);
        rst_n = 1;
        flush = 0;
        size = 0;
        head = 0;
        tail = 0;
    endtask

    initial begin
        #1000000;
        $fatal(1, "buffer watchdog");
    end

    initial begin
        @(negedge clk);
        reset_dma();
        cycle(0, 1, 0, 0);
        cycle(1, 1, 0, DATA_WIDTH'(17));
        for (i = 1; i < DEPTH; i = i + 1) begin
            cycle(1, 0, 0, DATA_WIDTH'(i + 17));
        end
        cycle(1, 0, 0, DATA_WIDTH'(999));
        cycle(1, 1, 0, DATA_WIDTH'(999));
        // Full rejects push despite accepted pop.
        cycle(1, 0, 0, DATA_WIDTH'(31));
        for (i = 0; i < DEPTH; i = i + 1) begin
            cycle(0, 1, 0, 0);
        end
        for (j = 0; j < 5; j = j + 1) begin
            for (i = 0; i < DEPTH; i = i + 1) begin
                cycle(1, 0, 0, DATA_WIDTH'(i + j));
            end
            for (i = 0; i < DEPTH; i = i + 1) begin
                cycle(0, 1, 0, 0);
            end
        end
        cycle(1, 0, 0, DATA_WIDTH'(111));
        cycle(1, 1, 1, DATA_WIDTH'(222));
        cycle(0, 1, 0, 0);
        for (i = 0; i < 10000; i = i + 1) begin
            rng = random_word();
            cycle(rng[0], rng[1], (rng[7:2] == 0), DATA_WIDTH'(rng));
        end
        reset_dma();
        cycle(1, 0, 0, DATA_WIDTH'(73));
        cycle(0, 1, 0, 0);
        $display("PASS buffer depth=%0d width=%0d seed=B00FCAFE cycles=10000", DEPTH, DATA_WIDTH);
        $finish;
    end

endmodule
`default_nettype wire
