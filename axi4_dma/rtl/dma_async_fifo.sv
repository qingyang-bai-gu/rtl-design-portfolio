`default_nettype none
// Dual-clock, show-ahead FIFO. Both domains must share reset assertion (see CDC.md).
// Only registered Gray pointers cross synchronizers; storage is written in wr_clk.
module dma_async_fifo #(
    parameter int unsigned DATA_WIDTH = 128,
    parameter int unsigned DEPTH = 4,
    localparam int unsigned DATA_BITS = DATA_WIDTH == 0 ? 1 : DATA_WIDTH,
    localparam int unsigned ADDRESS_BITS = DEPTH < 2 ? 1 : $clog2(DEPTH),
    localparam int unsigned POINTER_BITS = ADDRESS_BITS + 1
) (
    input logic wr_clk,
    input logic wr_rst_n,
    input logic [DATA_BITS-1:0] push_data,
    input logic push_valid,
    output logic push_ready,
    input logic rd_clk,
    input logic rd_rst_n,
    output logic [DATA_BITS-1:0] pop_data,
    output logic pop_valid,
    input logic pop_ready
);
    timeunit 1ns / 1ps;
    localparam logic [POINTER_BITS-1:0] FULL_MASK =
        (POINTER_BITS'(1) << (POINTER_BITS-1)) | (POINTER_BITS'(1) << (POINTER_BITS-2));
    logic [DATA_BITS-1:0] storage[DEPTH < 2 ? 2 : DEPTH];
    logic [POINTER_BITS-1:0] wr_binary;
    logic [POINTER_BITS-1:0] wr_gray;
    logic [POINTER_BITS-1:0] wr_binary_next;
    logic [POINTER_BITS-1:0] wr_gray_next;
    logic [POINTER_BITS-1:0] rd_binary;
    logic [POINTER_BITS-1:0] rd_gray;
    logic [POINTER_BITS-1:0] rd_binary_next;
    logic [POINTER_BITS-1:0] rd_gray_next;
    logic [POINTER_BITS-1:0] rd_gray_in_wr;
    logic [POINTER_BITS-1:0] wr_gray_in_rd;
    logic wr_full;
    logic rd_empty;
    logic push;
    logic pop;
    assign push_ready = wr_rst_n && !wr_full;
    assign pop_valid = rd_rst_n && !rd_empty;
    assign push = push_valid && push_ready;
    assign pop = pop_valid && pop_ready;
    assign wr_binary_next = wr_binary + POINTER_BITS'(push);
    assign rd_binary_next = rd_binary + POINTER_BITS'(pop);
    assign wr_gray_next = (wr_binary_next >> 1) ^ wr_binary_next;
    assign rd_gray_next = (rd_binary_next >> 1) ^ rd_binary_next;
    assign pop_data = storage[rd_binary[ADDRESS_BITS-1:0]];

    cdc_bit_sync #(
        .WIDTH(POINTER_BITS)
    ) read_pointer_sync (
        .clk(wr_clk),
        .rst_n(wr_rst_n),
        .async_data(rd_gray),
        .sync_data(rd_gray_in_wr)
    );
    cdc_bit_sync #(
        .WIDTH(POINTER_BITS)
    ) write_pointer_sync (
        .clk(rd_clk),
        .rst_n(rd_rst_n),
        .async_data(wr_gray),
        .sync_data(wr_gray_in_rd)
    );
    // Pointer reset is asynchronous so reset also cancels work with a stopped clock.
    always_ff @(posedge wr_clk or negedge wr_rst_n) begin
        if (!wr_rst_n) begin
            wr_binary <= '0;
            wr_gray <= '0;
            wr_full <= 1'b0;
        end else begin
            wr_binary <= wr_binary_next;
            wr_gray <= wr_gray_next;
            wr_full <= wr_gray_next == (rd_gray_in_wr ^ FULL_MASK);
        end
    end
    always_ff @(posedge wr_clk) begin
        if (push) begin
            storage[wr_binary[ADDRESS_BITS-1:0]] <= push_data;
        end
    end
    always_ff @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) begin
            rd_binary <= '0;
            rd_gray <= '0;
            rd_empty <= 1'b1;
        end else begin
            rd_binary <= rd_binary_next;
            rd_gray <= rd_gray_next;
            rd_empty <= rd_gray_next == wr_gray_in_rd;
        end
    end
`ifndef SYNTHESIS
    initial begin
        if (DATA_WIDTH == 0 || DEPTH < 2 || (DEPTH & (DEPTH - 1)) != 0) begin
            $fatal(1, "PARAM: async FIFO needs positive width and power-of-two depth >= 2");
        end
    end
`endif
endmodule
`default_nettype wire
