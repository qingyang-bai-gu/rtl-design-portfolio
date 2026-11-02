`timescale 1ns/1ps
`default_nettype none

module tb_async_fifo;
    parameter integer ADDR_BITS = 3;
    localparam integer DEPTH = 1 << ADDR_BITS;
    reg arst_n = 1, wr_clk = 0, rd_clk = 0;
    integer wr_half = 7, rd_half = 5;
    wire [15:0] rd_data;
    reg [15:0] wr_data = 0;
    reg wr_valid = 0, rd_ready = 0;
    wire wr_ready, rd_valid;
    fir_async_fifo #(.WIDTH(16), .ADDR_BITS(ADDR_BITS)) dut (.*);
    reg [15:0] queue [0:19999];
    integer writes = 0, reads = 0, mode = 0, full_cycles = 0, empty_cycles = 0;
    reg [31:0] wr_rng = 32'habcddcba, rd_rng = 32'h53142;
    reg [ADDR_BITS:0] prev_wr_gray = 0, prev_rd_gray = 0;
    reg [ADDR_BITS:0] delta_wr, delta_rd;

    initial begin
        if ($value$plusargs("WR_HALF=%d", wr_half)) begin end
        forever #(wr_half) wr_clk = !wr_clk;
    end
    initial begin
        if ($value$plusargs("RD_HALF=%d", rd_half)) begin end
        #2;
        forever #(rd_half) rd_clk = !rd_clk;
    end

    function automatic [31:0] step_rng(input [31:0] old);
        reg [31:0] v;
        begin
            v = old ^ (old << 13); v = v ^ (v >> 17); v = v ^ (v << 5);
            step_rng = v;
        end
    endfunction
    always @(negedge wr_clk) begin
        wr_rng = step_rng(wr_rng);
        wr_valid = arst_n && (mode == 1 || (mode == 3 && wr_rng[1:0] != 0));
        delta_wr = dut.wr_gray ^ prev_wr_gray;
        if ((delta_wr & (delta_wr - 1'b1)) != 0 && arst_n) $fatal(1, "Non-Gray write transition");
        prev_wr_gray = dut.wr_gray;
    end
    always @(negedge rd_clk) begin
        rd_rng = step_rng(rd_rng);
        rd_ready = arst_n && (mode == 2 || (mode == 3 && rd_rng[2:0] < 5));
        delta_rd = dut.rd_gray ^ prev_rd_gray;
        if ((delta_rd & (delta_rd - 1'b1)) != 0 && arst_n) $fatal(1, "Non-Gray read transition");
        prev_rd_gray = dut.rd_gray;
    end
    always @(posedge wr_clk or negedge arst_n) begin
        if (!arst_n) begin writes = 0; wr_data <= 0; full_cycles = 0; end
        else begin
            if (wr_valid && wr_ready) begin
                queue[writes] = wr_data;
                writes = writes + 1;
                wr_data <= wr_data + 16'h71c3;
            end
            if (!wr_ready && dut.wr_rst_n) full_cycles = full_cycles + 1;
            if (writes - reads > DEPTH) $fatal(1, "FIFO overflow");
        end
    end
    always @(posedge rd_clk or negedge arst_n) begin
        if (!arst_n) begin reads = 0; empty_cycles = 0; end
        else begin
            if (rd_valid && rd_ready) begin
                if (reads >= writes || rd_data !== queue[reads])
                    $fatal(1, "FIFO ordering/data failure index=%0d", reads);
                reads = reads + 1;
            end
            if (!rd_valid && dut.rd_rst_n) empty_cycles = empty_cycles + 1;
        end
    end

    task automatic reset_fifo;
        begin
            #1; arst_n = 0; mode = 0;
            repeat (8) @(negedge wr_clk);
            repeat (8) @(negedge rd_clk);
            prev_wr_gray = 0; prev_rd_gray = 0;
            #1; arst_n = 1;
        end
    endtask
    initial begin : test
        reset_fifo();
        mode = 1;
        wait (writes == DEPTH);
        repeat (12) @(negedge wr_clk);
        if (wr_ready || writes != DEPTH) $fatal(1, "FIFO full capacity error");
        mode = 2;
        wait (reads == DEPTH);
        repeat (12) @(negedge rd_clk);
        if (rd_valid) $fatal(1, "FIFO not empty after drain");
        mode = 3;
        repeat (3000) @(negedge wr_clk);
        mode = 2;
        repeat (4) @(negedge wr_clk);
        wait (reads == writes);
        repeat (10) @(negedge rd_clk);
        if (writes < DEPTH*10 || full_cycles == 0 || empty_cycles == 0)
            $fatal(1, "Insufficient FIFO coverage");
        $display("PASS FIFO depth=%0d writes=%0d full_cycles=%0d empty_cycles=%0d clocks=%0d/%0d",
            DEPTH, writes, full_cycles, empty_cycles, wr_half, rd_half);
        mode = 1;
        wait (!wr_ready);
        reset_fifo();
        repeat (8) @(negedge rd_clk);
        if (rd_valid || !wr_ready) $fatal(1, "FIFO reset recovery error");
        mode = 3;
        repeat (500) @(negedge wr_clk);
        mode = 2;
        repeat (4) @(negedge wr_clk);
        wait (reads == writes);
        $display("PASS FIFO reset recovery writes=%0d", writes);
        $finish;
    end
    initial begin #2000000; $fatal(1, "FIFO watchdog expired"); end
endmodule

`default_nettype wire
