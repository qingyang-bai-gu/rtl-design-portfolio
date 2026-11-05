`default_nettype none

module fifo_async #(
  parameter integer DEPTH = 8,
  parameter integer WIDTH = 8
) (
  input  wire             wr_clk,
  input  wire             rd_clk,
  input  wire             rst, // Active-high, asynchronous assertion, synchronous release
  input  wire             wr,
  input  wire             rd,
  input  wire [WIDTH-1:0] din,
  output reg  [WIDTH-1:0] dout,
  output reg              empty,
  output reg              full
);
  timeunit 1ns / 1ps;

  localparam ADDR_WIDTH = (DEPTH < 2) ? 1 : $clog2(DEPTH);
  localparam PTR_WIDTH = ADDR_WIDTH + 1;
  // Adding wrap bit to a binary pointer MSB. 
  // In Gray code, the same offset flips the top two bits.
  localparam [PTR_WIDTH-1:0] FULL_MASK = {2'b11, {(ADDR_WIDTH-1){1'b0}}};

  reg [WIDTH-1:0] mem [0:DEPTH-1];
  reg [PTR_WIDTH-1:0] wr_ptr_bin, wr_ptr_gray;
  reg [PTR_WIDTH-1:0] rd_ptr_bin, rd_ptr_gray;

  reg [1:0] wr_rst_pipe, rd_rst_pipe;
  // 2-flop synchronizer to sync pointers.
  reg [PTR_WIDTH-1:0] rd_ptr_gray_meta, rd_ptr_gray_sync;
  reg [PTR_WIDTH-1:0] wr_ptr_gray_meta, wr_ptr_gray_sync;

  wire wr_rst = wr_rst_pipe[1];
  wire rd_rst = rd_rst_pipe[1];
  wire wr_take = wr && !full && !wr_rst;
  wire rd_take = rd && !empty && !rd_rst;
  wire [PTR_WIDTH-1:0] wr_ptr_bin_next = wr_ptr_bin + PTR_WIDTH'(wr_take);
  wire [PTR_WIDTH-1:0] rd_ptr_bin_next = rd_ptr_bin + PTR_WIDTH'(rd_take);
  wire [PTR_WIDTH-1:0] wr_ptr_gray_next = (wr_ptr_bin_next >> 1) ^ wr_ptr_bin_next;
  wire [PTR_WIDTH-1:0] rd_ptr_gray_next = (rd_ptr_bin_next >> 1) ^ rd_ptr_bin_next;

  always @(posedge wr_clk or posedge rst) begin
    if (rst) wr_rst_pipe <= '1;
    else     wr_rst_pipe <= {wr_rst_pipe[0], 1'b0};
  end

  always @(posedge rd_clk or posedge rst) begin
    if (rst) rd_rst_pipe <= '1;
    else     rd_rst_pipe <= {rd_rst_pipe[0], 1'b0};
  end

  // Write clock domain:
  always @(posedge wr_clk or posedge wr_rst) begin
    if (wr_rst) begin
      rd_ptr_gray_meta <= '0;
      rd_ptr_gray_sync <= '0;
      wr_ptr_bin <= '0;
      wr_ptr_gray <= '0;
      full <= 1'b0;
    end else begin
      rd_ptr_gray_meta <= rd_ptr_gray;
      rd_ptr_gray_sync <= rd_ptr_gray_meta;
      wr_ptr_bin <= wr_ptr_bin_next;
      wr_ptr_gray <= wr_ptr_gray_next;
      full <= (wr_ptr_gray_next == (rd_ptr_gray_sync ^ FULL_MASK));
    end
  end

  // Read clock domain:
  always @(posedge rd_clk or posedge rd_rst) begin
    if (rd_rst) begin
      wr_ptr_gray_meta <= '0;
      wr_ptr_gray_sync <= '0;
      rd_ptr_bin <= '0;
      rd_ptr_gray <= '0;
      empty <= 1'b1;
    end else begin
      wr_ptr_gray_meta <= wr_ptr_gray;
      wr_ptr_gray_sync <= wr_ptr_gray_meta;
      rd_ptr_bin <= rd_ptr_bin_next;
      rd_ptr_gray <= rd_ptr_gray_next;
      empty <= (rd_ptr_gray_next == wr_ptr_gray_sync);
    end
  end

  // Keep storage and dout updates clocked only.
  always @(posedge wr_clk) begin
    if (wr_take) begin
      mem[wr_ptr_bin[ADDR_WIDTH-1:0]] <= din;
    end
  end

  always @(posedge rd_clk) begin
    if (rd_take) begin
      dout <= mem[rd_ptr_bin[ADDR_WIDTH-1:0]];
    end
  end

`ifndef SYNTHESIS
  initial begin
    if (WIDTH < 1 || DEPTH < 2 || (DEPTH & (DEPTH - 1)) != 0)
      $fatal(1, "fifo_async requires WIDTH >= 1 and a power-of-two DEPTH >= 2");
  end
`endif
endmodule

`default_nettype wire
