`default_nettype none
module tb_async_fifo;
    timeunit 1ns / 1ps;
    parameter int unsigned DATA_WIDTH = 128;
    parameter int unsigned DEPTH = 4;
    parameter int unsigned WR_HALF = 3;
    parameter int unsigned RD_HALF = 5;
    parameter int unsigned RD_PHASE = 1;
    logic wr_clk = 0;
    logic rd_clk = 0;
    logic wr_enable = 1;
    logic rd_enable = 1;
    logic arst_n = 0;
    logic wr_rst_n;
    logic rd_rst_n;
    logic [DATA_WIDTH-1:0] push_data = '0;
    logic push_valid = 0;
    logic push_ready;
    logic [DATA_WIDTH-1:0] pop_data;
    logic pop_valid;
    logic pop_ready = 0;
    logic produce = 0;
    logic consume = 0;
    logic random_traffic = 0;
    logic [31:0] wr_rng = 32'h5B00318F;
    logic [31:0] rd_rng = 32'h701ABB9E;
    int written = 0;
    int read_count = 0;
    int target = 0;
    int reset_count = 0;
    logic accepted = 0;
    logic [DATA_WIDTH-1:0] expected[8192];
    initial begin
        forever begin
            #(WR_HALF);
            if (wr_enable) begin
                wr_clk = !wr_clk;
            end else begin
                wr_clk = 0;
            end
        end
    end
    initial begin
        #(RD_PHASE);
        forever begin
            #(RD_HALF);
            if (rd_enable) begin
                rd_clk = !rd_clk;
            end else begin
                rd_clk = 0;
            end
        end
    end
    reset_sync write_reset (
        .clk(wr_clk),
        .arst_n(arst_n),
        .rst_n(wr_rst_n)
    );
    reset_sync read_reset (
        .clk(rd_clk),
        .arst_n(arst_n),
        .rst_n(rd_rst_n)
    );
    dma_async_fifo #(
        .DATA_WIDTH(DATA_WIDTH),
        .DEPTH(DEPTH)
    ) dut (
        .wr_clk(wr_clk),
        .wr_rst_n(wr_rst_n),
        .push_data(push_data),
        .push_valid(push_valid),
        .push_ready(push_ready),
        .rd_clk(rd_clk),
        .rd_rst_n(rd_rst_n),
        .pop_data(pop_data),
        .pop_valid(pop_valid),
        .pop_ready(pop_ready)
    );
    rv_stability #(
        .WIDTH(DATA_WIDTH)
    ) push_hold (
        .clk(wr_clk),
        .rst_n(wr_rst_n),
        .valid(push_valid),
        .ready(push_ready),
        .payload(push_data)
    );
    rv_stability #(
        .WIDTH(DATA_WIDTH)
    ) pop_hold (
        .clk(rd_clk),
        .rst_n(rd_rst_n),
        .valid(pop_valid),
        .ready(pop_ready),
        .payload(pop_data)
    );
    // Interface-only queue: no pointer, synchronizer, full, or empty DUT state is read.
    always @(posedge wr_clk or negedge wr_rst_n) begin
        if (!wr_rst_n) begin
            written = 0;
            accepted = 0;
        end else begin
            accepted = push_valid && push_ready;
            if (accepted) begin
                if (written - read_count >= DEPTH || written >= 8192) begin
                    $fatal(1, "FIFO accepted overflow");
                end
                expected[written] = push_data;
                written = written + 1;
            end
        end
    end
    always @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) begin
            read_count = 0;
        end else if (pop_valid && pop_ready) begin
            if (read_count >= written) begin
                $fatal(1, "FIFO accepted underflow");
            end
            if (pop_data !== expected[read_count]) begin
                $fatal(1, "FIFO loss/reorder/duplicate at %0d", read_count);
            end
            read_count = read_count + 1;
        end
    end
    always @(negedge wr_clk or negedge wr_rst_n) begin
        if (!wr_rst_n) begin
            push_valid = 0;
        end else begin
            if (accepted) begin
                push_valid = 0;
            end
            wr_rng = wr_rng ^ (wr_rng << 13);
            wr_rng = wr_rng ^ (wr_rng >> 17);
            wr_rng = wr_rng ^ (wr_rng << 5);
            if (!push_valid && produce && written < target && (!random_traffic || wr_rng[0])) begin
                for (int bit_number = 0; bit_number < DATA_WIDTH; bit_number = bit_number + 1) begin
                    push_data[bit_number] = wr_rng[bit_number%32] ^ 1'(written >> (bit_number%13));
                end
                push_valid = 1;
            end
        end
    end
    always @(negedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) begin
            pop_ready = 0;
        end else begin
            rd_rng = rd_rng ^ (rd_rng << 13);
            rd_rng = rd_rng ^ (rd_rng >> 17);
            rd_rng = rd_rng ^ (rd_rng << 5);
            pop_ready = consume && (!random_traffic || rd_rng[1:0] == 0);
        end
    end
    task automatic drain();
        consume = 1;
        wait (read_count == target);
        @(negedge rd_clk);
        #0.1;
        produce = 0;
        repeat (8) begin
            @(negedge rd_clk);
        end
        if (pop_valid || written != read_count) begin
            $fatal(1, "FIFO did not drain exactly");
        end
    endtask
    task automatic reset_all();
        produce = 0;
        consume = 0;
        #0.3;
        arst_n = 0;
        #1;
        if (push_ready || pop_valid) begin
            $fatal(1, "FIFO reset suppression");
        end
        #(10 * (WR_HALF + RD_HALF));
        arst_n = 1;
        reset_count = reset_count + 1;
    endtask
    initial begin
        #11;
        arst_n = 1;
        wait (wr_rst_n && rd_rst_n);
        target = DEPTH;
        produce = 1;
        wait (written == target);
        repeat (8) begin
            @(negedge wr_clk);
        end
        if (push_ready || !pop_valid) begin
            $fatal(1, "FIFO full capacity");
        end
        drain();
        target = 2048;
        random_traffic = 1;
        produce = 1;
        drain();
        consume = 0;
        target = written + DEPTH;
        produce = 1;
        wait (written == target);
        @(negedge rd_clk);
        #0.1;
        rd_enable = 0;
        reset_all();
        repeat (12) begin
            @(negedge wr_clk);
        end
        if (rd_rst_n || pop_valid || !push_ready) begin
            $fatal(1, "FIFO stopped reader reset");
        end
        rd_enable = 1;
        wait (rd_rst_n);
        target = 512;
        produce = 1;
        drain();
        consume = 0;
        target = written + DEPTH;
        produce = 1;
        wait (written == target);
        @(negedge wr_clk);
        #0.1;
        wr_enable = 0;
        reset_all();
        repeat (12) begin
            @(negedge rd_clk);
        end
        if (wr_rst_n || pop_valid) begin
            $fatal(1, "FIFO stopped writer reset");
        end
        wr_enable = 1;
        wait (wr_rst_n);
        target = 512;
        produce = 1;
        drain();
        $display("PASS async FIFO width=%0d depth=%0d resets=%0d seed=5B00318F/701ABB9E",
                 DATA_WIDTH, DEPTH, reset_count);
        $finish;
    end
    initial begin
        #2000000;
        $fatal(1, "async FIFO watchdog written=%0d read=%0d", written, read_count);
    end
endmodule
`default_nettype wire
