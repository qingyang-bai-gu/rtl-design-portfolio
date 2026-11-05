`default_nettype none

module fifo_async #(
  parameter integer DEPTH = 8,
  parameter integer WIDTH = 8
) (
  input  wire             wr_clk,
  input  wire             rd_clk,
  input  wire             rst,
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
  // Adding DEPTH to a binary pointer flips its top bit. In Gray code,
  // the same offset flips the top two bits, including at DEPTH = 2.
  localparam [PTR_WIDTH-1:0] FULL_MASK = {2'b11, {(ADDR_WIDTH-1){1'b0}}};

  reg [WIDTH-1:0] mem [0:DEPTH-1];
  reg [PTR_WIDTH-1:0] wr_ptr, wr_gray;
  reg [PTR_WIDTH-1:0] rd_ptr, rd_gray;

  (* ASYNC_REG = "TRUE" *) reg [1:0] wr_reset_pipe, rd_reset_pipe;
  (* ASYNC_REG = "TRUE" *) reg [PTR_WIDTH-1:0] rd_gray_meta, rd_gray_sync;
  (* ASYNC_REG = "TRUE" *) reg [PTR_WIDTH-1:0] wr_gray_meta, wr_gray_sync;

  wire wr_reset = wr_reset_pipe[1];
  wire rd_reset = rd_reset_pipe[1];
  wire wr_take = wr && !full && !wr_reset;
  wire rd_take = rd && !empty && !rd_reset;
  wire [PTR_WIDTH-1:0] wr_ptr_next = wr_ptr + PTR_WIDTH'(wr_take);
  wire [PTR_WIDTH-1:0] rd_ptr_next = rd_ptr + PTR_WIDTH'(rd_take);
  wire [PTR_WIDTH-1:0] wr_gray_next = (wr_ptr_next >> 1) ^ wr_ptr_next;
  wire [PTR_WIDTH-1:0] rd_gray_next = (rd_ptr_next >> 1) ^ rd_ptr_next;

  // Reset asserts in both domains even when one clock is stopped.
  // Each domain releases reset on its own clock.
  always @(posedge wr_clk or posedge rst) begin
    if (rst) wr_reset_pipe <= '1;
    else     wr_reset_pipe <= {wr_reset_pipe[0], 1'b0};
  end

  always @(posedge rd_clk or posedge rst) begin
    if (rst) rd_reset_pipe <= '1;
    else     rd_reset_pipe <= {rd_reset_pipe[0], 1'b0};
  end

  always @(posedge wr_clk or posedge wr_reset) begin
    if (wr_reset) begin
      rd_gray_meta <= '0;
      rd_gray_sync <= '0;
      wr_ptr <= '0;
      wr_gray <= '0;
      full <= 1'b0;
    end else begin
      rd_gray_meta <= rd_gray;
      rd_gray_sync <= rd_gray_meta;
      wr_ptr <= wr_ptr_next;
      wr_gray <= wr_gray_next;
      full <= (wr_gray_next == (rd_gray_sync ^ FULL_MASK));
    end
  end

  always @(posedge rd_clk or posedge rd_reset) begin
    if (rd_reset) begin
      wr_gray_meta <= '0;
      wr_gray_sync <= '0;
      rd_ptr <= '0;
      rd_gray <= '0;
      empty <= 1'b1;
    end else begin
      wr_gray_meta <= wr_gray;
      wr_gray_sync <= wr_gray_meta;
      rd_ptr <= rd_ptr_next;
      rd_gray <= rd_gray_next;
      empty <= (rd_gray_next == wr_gray_sync);
    end
  end

  always @(posedge wr_clk) begin
    if (wr_take) mem[wr_ptr[ADDR_WIDTH-1:0]] <= din;
  end

  always @(posedge rd_clk) begin
    if (rd_take) dout <= mem[rd_ptr[ADDR_WIDTH-1:0]];
  end

`ifndef SYNTHESIS
  initial begin
    if (WIDTH < 1 || DEPTH < 2 || (DEPTH & (DEPTH - 1)) != 0)
      $fatal(1, "fifo_async requires WIDTH >= 1 and a power-of-two DEPTH >= 2");
  end
`endif
endmodule

`default_nettype wire
