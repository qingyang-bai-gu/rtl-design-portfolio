module fifo_sync #(
  parameter DEPTH = 8,
  parameter WIDTH = 8
) (
  input clk,
  input rst,
  input wr,
  input rd,
  input [WIDTH-1:0] din,
  output reg [WIDTH-1:0] dout,
  output empty,
  output full
);
  localparam ADDR_WIDTH = $clog2(DEPTH);
  
  reg [WIDTH-1:0] mem [0:DEPTH-1];
  
  reg [ADDR_WIDTH:0] wr_ptr;
  reg [ADDR_WIDTH:0] rd_ptr;
  wire [ADDR_WIDTH:0] wr_ptr_next;
  wire [ADDR_WIDTH:0] rd_ptr_next; 
  
  assign wr_ptr_next = (wr_ptr[ADDR_WIDTH-1:0] == DEPTH - 1) ? {~wr_ptr[ADDR_WIDTH], {ADDR_WIDTH{1'b0}}} : (wr_ptr + 1);
  assign rd_ptr_next = (rd_ptr[ADDR_WIDTH-1:0] == DEPTH - 1) ? {~rd_ptr[ADDR_WIDTH], {ADDR_WIDTH{1'b0}}} : (rd_ptr + 1);
  
  always @(posedge clk) begin
    if (rst) begin
      wr_ptr <= 0;
    end else if (wr && (!full || rd)) begin  // Allows for simultaneous read and write when full
      mem[wr_ptr[ADDR_WIDTH-1:0]] <= din;
      wr_ptr <= wr_ptr_next;
    end
  end
  
  always @(posedge clk) begin
    if (rst) begin
      rd_ptr <= 0;
    end else if (rd && !empty) begin
      dout <= mem[rd_ptr[ADDR_WIDTH-1:0]];
      rd_ptr <= rd_ptr_next;
    end
  end
    
  assign empty = (wr_ptr == rd_ptr);
  assign full  = (wr_ptr[ADDR_WIDTH] != rd_ptr[ADDR_WIDTH]) && (wr_ptr[ADDR_WIDTH-1:0] == rd_ptr[ADDR_WIDTH-1:0]);
  
endmodule
