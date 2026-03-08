module tb_fifo ();

parameter DEPTH = 10;
parameter WIDTH = 8;

reg clk;
reg rst;
reg rd;
reg wr;
reg [WIDTH-1:0] din;

wire [WIDTH-1:0] dout;
wire empty;
wire full;

fifo_sync #(
  .DEPTH(DEPTH),
  .WIDTH(WIDTH)
) dut (
  .clk(clk),
  .rst(rst),
  .wr(wr),
  .rd(rd),
  .din(din),
  .dout(dout),
  .empty(empty),
  .full(full)
);

////////////////////////////////////////////////
// Clock
////////////////////////////////////////////////

initial clk = 0;
always #5 clk = ~clk;

////////////////////////////////////////////////
// Reference Model
////////////////////////////////////////////////

logic [WIDTH-1:0] ref_fifo[$];
logic [WIDTH-1:0] dout_expected;
logic empty_expected;
logic full_expected;
logic wr_en;
logic rd_en;

always @(posedge clk) begin
  if (!rst) begin

    #1; // allow DUT state to settle

    empty_expected = (ref_fifo.size() == 0);
    full_expected  = (ref_fifo.size() == DEPTH);

    wr_en = wr && (!full_expected || rd);
    rd_en = rd && !empty_expected;

    if (wr_en) begin
      $display("Write @ time=%0t din=%0d empty=%0d full=%0d queue=%0d",
                $time, din, empty, full, ref_fifo.size());
      ref_fifo.push_back(din);
    end

    if (rd_en) begin
      dout_expected = ref_fifo.pop_front();

      $display("Read  @ time=%0t actual=%0d expected=%0d empty=%0d full=%0d queue=%0d",
                $time, dout, dout_expected, empty, full, ref_fifo.size());

      if (dout !== dout_expected) begin
        $display("ERROR: DOUT mismatch");
        $stop;
      end
    end

    empty_expected = (ref_fifo.size() == 0);
    full_expected  = (ref_fifo.size() == DEPTH);

    if (empty !== empty_expected) begin
      $display("ERROR: EMPTY flag incorrect");
      $stop;
    end

    if (full !== full_expected) begin
      $display("ERROR: FULL flag incorrect");
      $stop;
    end

  end
end
  
////////////////////////////////////////////////
// Reset
////////////////////////////////////////////////

initial begin
  rst = 1;
  wr  = 0;
  rd  = 0;
  din = 0;

  repeat(5) @(posedge clk);

  rst = 0;
end

////////////////////////////////////////////////
// Directed tasks
////////////////////////////////////////////////

task write(input [WIDTH-1:0] data);
begin
  @(negedge clk);
  wr  = 1;
  rd  = 0;
  din = data;

  @(negedge clk);
  wr = 0;
end
endtask

task read();
begin
  @(negedge clk);
  wr = 0;
  rd = 1;

  @(negedge clk);
  rd = 0;
end
endtask

////////////////////////////////////////////////
// Test sequence
////////////////////////////////////////////////

initial begin

  wait(!rst);

  $display("Starting directed tests");

  repeat(5)
    write($random);

  repeat(5)
    read();

  repeat(DEPTH+1)
    write($random);

  repeat(DEPTH+1)
    read();

  $display("Starting random stress tests");

  repeat(1000) begin
    @(negedge clk);
    wr  = $random % 2;
    rd  = $random % 2;
    din = $random;
  end

  repeat(10) @(posedge clk);

  $display("PASS");
  $finish;

end

endmodule
