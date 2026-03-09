`timescale 1ns/1ps

module mac_3stage_tb;

  parameter W = 16;
  parameter W_OUT = 32;

  // DUT signals

  logic clk;
  logic areset;
  logic valid_in;
  logic [W-1:0] a;
  logic [W-1:0] b;

  logic [W_OUT-1:0] dout;
  logic valid_out;

  // Instantiate DUT

  mac_3stage #(
    .W(W),
    .W_OUT(W_OUT)
  ) dut (
    .clk(clk),
    .areset(areset),
    .a(a),
    .b(b),
    .valid_in(valid_in),
    .dout(dout),
    .valid_out(valid_out)
  );

  // Clock generation

  initial clk = 0;
  always #5 clk = ~clk;   // 100MHz clock

  // Waveform dump

  initial begin
    $dumpfile("mac_wave.vcd");
    $dumpvars(0, mac_3stage_tb);
  end

  // Reference model

  logic [W_OUT-1:0] acc_ref;

  // Pipeline tracking (for latency alignment)

  logic valid_pipe [0:2];
  logic [W_OUT-1:0] expected_pipe [0:2];

  // Reset

  initial begin
    areset = 1;
    valid_in = 0;
    a = 0;
    b = 0;

    repeat(5) @(posedge clk);

    areset = 0;
  end

  // Random Stimulus

  initial begin

    wait(!areset);

    repeat (1000) begin
      @(posedge clk);

      valid_in <= $urandom_range(0,1);

      if (valid_in) begin
        a <= $urandom_range(0, 2**W-1);
        b <= $urandom_range(0, 2**W-1);
      end
    end

    repeat(10) @(posedge clk);

    $finish;

  end

  // Reference model computation

  always_ff @(posedge clk) begin

    if (areset) begin
      acc_ref <= 0;
      valid_pipe[0] <= 0;
      valid_pipe[1] <= 0;
      valid_pipe[2] <= 0;
    end
    else begin

      logic [W_OUT-1:0] acc_next;

      acc_next = acc_ref;

      if (valid_in)
        acc_next = acc_ref + (a * b);

      acc_ref <= acc_next;

      valid_pipe[0] <= valid_in;
      valid_pipe[1] <= valid_pipe[0];
      valid_pipe[2] <= valid_pipe[1];

      expected_pipe[0] <= acc_next;
      expected_pipe[1] <= expected_pipe[0];
      expected_pipe[2] <= expected_pipe[1];

    end

  end

  // Check results

  always_ff @(posedge clk) begin

    if (!areset && valid_out) begin

      if (dout !== expected_pipe[2]) begin
        $display("ERROR at time %0t", $time);
        $display("Expected: %0d  Got: %0d",
                 expected_pipe[2], dout);
        $fatal;
      end
      else begin
        $display("PASS time=%0t result=%0d", $time, dout);
      end

    end

  end

endmodule
