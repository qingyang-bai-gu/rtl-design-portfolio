module tb_fifo_async #(
  parameter integer DEPTH = 8,
  parameter integer WIDTH = 8,
  parameter integer WR_HALF_PERIOD = 5,
  parameter integer RD_HALF_PERIOD = 7
);
  timeunit 1ns / 1ps;

  reg wr_clk = 0;
  reg rd_clk = 0;
  reg wr_clk_run = 1;
  reg rd_clk_run = 1;
  reg rst = 0;
  reg wr = 0;
  reg rd = 0;
  reg [WIDTH-1:0] din = '0;
  wire [WIDTH-1:0] dout;
  wire empty, full;

  fifo_async #(.DEPTH(DEPTH), .WIDTH(WIDTH)) dut (
    .wr_clk(wr_clk), .rd_clk(rd_clk), .rst(rst), .wr(wr), .rd(rd),
    .din(din), .dout(dout), .empty(empty), .full(full)
  );

  always #(WR_HALF_PERIOD) if (wr_clk_run) wr_clk = ~wr_clk;
  always #(RD_HALF_PERIOD) if (rd_clk_run) rd_clk = ~rd_clk;

  reg [WIDTH-1:0] expected_mem [0:DEPTH-1];
  reg [WIDTH-1:0] expected_dout;
  integer writes, reads;

  // Nonblocking model updates let both monitors see pre-edge occupancy
  // when the independent clocks have coincident rising edges.
  always @(posedge wr_clk or posedge rst) begin
    if (rst) begin
      writes <= 0;
    end else if (wr && !full) begin
      if (writes - reads >= DEPTH) $fatal(1, "FIFO overflow");
      expected_mem[writes % DEPTH] <= din;
      writes <= writes + 1;
    end
  end

  always @(posedge rd_clk or posedge rst) begin
    if (rst) begin
      reads <= 0;
      expected_dout <= 'x;
    end else if (rd && !empty) begin
      if (reads >= writes) $fatal(1, "FIFO underflow");
      expected_dout <= expected_mem[reads % DEPTH];
      reads <= reads + 1;
    end
  end

  always @(negedge rd_clk) begin
    if (reads != 0 && dout !== expected_dout)
      $fatal(1, "Read %0d: expected %h, got %h", reads, expected_dout, dout);
  end

  task automatic pulse_rst;
    #1 rst = 1;
    #1;
    if (full !== 1'b0 || empty !== 1'b1)
      $fatal(1, "Incorrect reset flags");
    #1 rst = 0;
  endtask

  task automatic wait_for_rst_release;
    fork
      repeat (3) @(negedge wr_clk);
      repeat (3) @(negedge rd_clk);
    join
  endtask

  task automatic write_cycles(input integer cycles);
    repeat (cycles) begin
      @(negedge wr_clk);
      wr = 1;
      din = WIDTH'($urandom);
    end
    @(negedge wr_clk);
    wr = 0;
  endtask

  task automatic read_cycles(input integer cycles);
    @(negedge rd_clk);
    rd = 1;
    repeat (cycles) @(negedge rd_clk);
    rd = 0;
  endtask

  initial begin
    pulse_rst();
    wait_for_rst_release();
    read_cycles(3);
    if (reads != 0 || empty !== 1'b1) $fatal(1, "Read accepted while empty");

    // Fill every slot, reject extra writes, drain in order and wrap pointers.
    for (integer round = 1; round <= 3; round = round + 1) begin
      write_cycles(DEPTH + 2);
      if (writes != round * DEPTH || full !== 1'b1)
        $fatal(1, "FIFO did not stop at its configured capacity");
      // Wait for the final write to reach the read domain before draining.
      repeat (3) @(negedge rd_clk);
      read_cycles(DEPTH + 2);
      if (reads != writes || empty !== 1'b1)
        $fatal(1, "FIFO did not drain completely");
      repeat (4) @(negedge wr_clk);
      if (full !== 1'b0) $fatal(1, "Full did not clear after reads");
    end

    // Assert reset with unread data and both requests high while the clocks are stopped.
    begin : check_pending_rst
      integer wr_addr;
      reg [WIDTH-1:0] mem_before_rst;

      @(negedge wr_clk);
      wr = 1;
      din = '0;
      @(negedge wr_clk);
      din = '1;
      @(negedge wr_clk);
      wr = 0;

      repeat (3) @(negedge rd_clk);
      read_cycles(1);
      repeat (4) @(negedge wr_clk);
      if (dout !== '0 || empty !== 1'b0 || full !== 1'b0)
        $fatal(1, "Reset test needs one unread word and space for a write");

      wr_addr = writes % DEPTH;
      mem_before_rst = dut.mem[wr_addr];
      fork
        begin
          @(negedge wr_clk);
          wr_clk_run = 0;
          wr = 1;
          din = ~mem_before_rst;
        end
        begin
          @(negedge rd_clk);
          rd_clk_run = 0;
          rd = 1;
        end
      join

      pulse_rst();
      if (dout !== '0 || dut.mem[wr_addr] !== mem_before_rst)
        $fatal(1, "FIFO data changed on reset without a clock edge");

      wr = 0;
      rd = 0;
      wr_clk_run = 1;
      rd_clk_run = 1;
    end
    wait_for_rst_release();
    read_cycles(3);
    if (reads != 0 || empty !== 1'b1) $fatal(1, "Reset did not flush the FIFO");

    fork
      begin
        repeat (1000) begin
          @(negedge wr_clk);
          wr = 1'($urandom);
          din = WIDTH'($urandom);
        end
        @(negedge wr_clk);
        wr = 0;
      end
      begin
        repeat (1000) begin
          @(negedge rd_clk);
          rd = 1'($urandom);
        end
        @(negedge rd_clk);
        rd = 0;
      end
    join

    repeat (3) @(negedge rd_clk);
    read_cycles(DEPTH + 2);
    if (reads != writes || empty !== 1'b1 || writes < 4 * DEPTH)
      $fatal(1, "Random test did not wrap and drain the FIFO");

    $display("PASS DEPTH=%0d WIDTH=%0d WR_HALF_PERIOD=%0d RD_HALF_PERIOD=%0d (%0d random writes/reads)",
             DEPTH, WIDTH, WR_HALF_PERIOD, RD_HALF_PERIOD, writes);
    $finish;
  end

  initial begin
    #100000;
    $fatal(1, "Simulation timed out");
  end
endmodule
