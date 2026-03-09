module mac_3stage #(
  parameter W = 16,
  parameter W_OUT = 2*W
)(
  input logic clk,
  input logic areset,
  input logic [W-1:0] a,
  input logic [W-1:0] b,
  input logic valid_in,
  
  output logic [W_OUT-1:0] dout,
  output logic valid_out
);
  
  logic [W-1:0] a_s1;
  logic [W-1:0] b_s1;
  logic valid_s1;
  logic [2*W-1:0] mult_s2;
  logic valid_s2;
  logic [W_OUT-1:0] acc_s3;
  
  assign dout = acc_s3;
  
  // Pipeline stage 1: input register
  
  always_ff @(posedge clk, posedge areset) begin
    if (areset) begin
      a_s1 <= '0;
      b_s1 <= '0;
      valid_s1 <= 1'b0;
    end else begin
      a_s1 <= a;
      b_s1 <= b;
      valid_s1 <= valid_in;
    end
  end
  
  // Pipeline stage 2: multiply
  
  always_ff @(posedge clk, posedge areset) begin
    if (areset) begin 
      mult_s2 <= '0;
      valid_s2 <= 1'b0;
    end else begin
      if (valid_s1) mult_s2 <= a_s1 * b_s1;
      valid_s2 <= valid_s1;
    end
  end
  
  // Pipeline stage 3: accumulate
  
  always_ff @(posedge clk, posedge areset) begin
    if (areset) begin 
      acc_s3 <= '0;
      valid_out <= 1'b0;
    end else begin
      if (valid_s2) acc_s3 <= acc_s3 + mult_s2;
      valid_out <= valid_s2;
    end
  end
  
endmodule
