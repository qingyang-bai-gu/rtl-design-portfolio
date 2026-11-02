`timescale 1ns/1ps
`default_nettype none

// Power-of-two depth, full capacity, first-word-fall-through read interface.
// Both domains must share arst_n. Independent domain resets are unsupported.
module fir_async_fifo #(
    parameter integer WIDTH = 16,
    parameter integer ADDR_BITS = 3
) (
    input  wire                 arst_n,
    input  wire                 wr_clk,
    input  wire [WIDTH-1:0]     wr_data,
    input  wire                 wr_valid,
    output wire                 wr_ready,
    input  wire                 rd_clk,
    output wire [WIDTH-1:0]     rd_data,
    output wire                 rd_valid,
    input  wire                 rd_ready
);
    localparam integer DEPTH = 1 << ADDR_BITS;
    localparam integer PTR_BITS = ADDR_BITS + 1;
    wire wr_rst_n, rd_rst_n;
    fir_reset_sync u_wr_reset (.clk(wr_clk), .arst_n(arst_n), .rst_n(wr_rst_n));
    fir_reset_sync u_rd_reset (.clk(rd_clk), .arst_n(arst_n), .rst_n(rd_rst_n));

    reg [WIDTH-1:0] mem [0:DEPTH-1];
    reg [PTR_BITS-1:0] wr_bin, wr_gray, rd_bin, rd_gray;
    (* ASYNC_REG = "TRUE" *) reg [PTR_BITS-1:0] rd_gray_sync1, rd_gray_sync2;
    (* ASYNC_REG = "TRUE" *) reg [PTR_BITS-1:0] wr_gray_sync1, wr_gray_sync2;
    reg full, empty;

    wire wr_take = wr_valid && wr_ready;
    wire rd_take = rd_valid && rd_ready;
    wire [PTR_BITS-1:0] wr_bin_next = wr_bin + {{ADDR_BITS{1'b0}}, wr_take};
    wire [PTR_BITS-1:0] rd_bin_next = rd_bin + {{ADDR_BITS{1'b0}}, rd_take};
    wire [PTR_BITS-1:0] wr_gray_next = (wr_bin_next >> 1) ^ wr_bin_next;
    wire [PTR_BITS-1:0] rd_gray_next = (rd_bin_next >> 1) ^ rd_bin_next;
    // Invert the top two Gray bits to distinguish pointers one full lap apart.
    wire [PTR_BITS-1:0] full_compare = rd_gray_sync2 ^ ((1 << ADDR_BITS) | (1 << (ADDR_BITS-1)));

    assign wr_ready = wr_rst_n && !full;
    assign rd_valid = rd_rst_n && !empty;
    assign rd_data = mem[rd_bin[ADDR_BITS-1:0]];

    always @(posedge wr_clk) begin
        if (wr_take) mem[wr_bin[ADDR_BITS-1:0]] <= wr_data;
    end
    always @(posedge wr_clk or negedge wr_rst_n) begin
        if (!wr_rst_n) begin
            wr_bin <= 0;
            wr_gray <= 0;
            full <= 0;
            rd_gray_sync1 <= 0;
            rd_gray_sync2 <= 0;
        end else begin
            rd_gray_sync1 <= rd_gray;
            rd_gray_sync2 <= rd_gray_sync1;
            wr_bin <= wr_bin_next;
            wr_gray <= wr_gray_next;
            full <= (wr_gray_next == full_compare);
        end
    end
    always @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) begin
            rd_bin <= 0;
            rd_gray <= 0;
            empty <= 1;
            wr_gray_sync1 <= 0;
            wr_gray_sync2 <= 0;
        end else begin
            wr_gray_sync1 <= wr_gray;
            wr_gray_sync2 <= wr_gray_sync1;
            rd_bin <= rd_bin_next;
            rd_gray <= rd_gray_next;
            empty <= (rd_gray_next == wr_gray_sync2);
        end
    end

`ifndef SYNTHESIS
    initial begin
        if (ADDR_BITS < 1 || ADDR_BITS > 16 || WIDTH < 1)
            $fatal(1, "fir_async_fifo requires WIDTH >= 1 and 1 <= ADDR_BITS <= 16");
    end
`endif
endmodule

`default_nettype wire
