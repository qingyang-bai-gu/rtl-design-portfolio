`default_nettype none
// Show-ahead data FIFO with conservative full/empty boundaries and logical-only flush.
module dma_burst_buffer #(
    parameter int unsigned DATA_WIDTH = 128,
    parameter int unsigned DEPTH = 16,
    parameter int unsigned COUNT_WIDTH = (DEPTH <= 1 ? 1 : $clog2(64'(DEPTH) + 64'd1)),
    localparam int unsigned DATA_BITS = DATA_WIDTH == 0 ? 1 : DATA_WIDTH,
    localparam int unsigned OCC_BITS = COUNT_WIDTH == 0 ? 1 : COUNT_WIDTH
) (
    input logic clk,
    input logic rst_n,
    input logic flush,
    input logic [DATA_BITS-1:0] push_data,
    input logic push_valid,
    output logic push_ready,
    output logic [DATA_BITS-1:0] pop_data,
    output logic pop_valid,
    input logic pop_ready,
    output logic [OCC_BITS-1:0] occupancy,
    output logic empty,
    output logic full
);
    timeunit 1ns / 1ps;

    localparam int unsigned PTR_WIDTH = DEPTH <= 1 ? 1 : $clog2(DEPTH);
    logic [PTR_WIDTH-1:0] rd_ptr;
    logic [PTR_WIDTH-1:0] wr_ptr;
    logic [DATA_BITS-1:0] storage[(DEPTH > 0 ? DEPTH : 1)];
    logic push;
    logic pop;
    logic [1:0] transfers;
    assign push = push_valid && push_ready;
    assign pop = pop_valid && pop_ready;
    assign transfers = {push, pop};
    assign empty = occupancy == 0;
    assign full = occupancy == OCC_BITS'(DEPTH);
    assign push_ready = rst_n && !flush && !full;
    assign pop_valid = rst_n && !flush && !empty;
    assign pop_data = storage[rd_ptr];

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            rd_ptr <= '0;
            wr_ptr <= '0;
            occupancy <= '0;
        end else if (flush) begin
            rd_ptr <= '0;
            wr_ptr <= '0;
            occupancy <= '0;
        end else begin
            if (push) begin
                storage[wr_ptr] <= push_data;
                if (wr_ptr == PTR_WIDTH'(DEPTH - 1)) begin
                    wr_ptr <= '0;
                end else begin
                    wr_ptr <= wr_ptr + 1'b1;
                end
            end
            if (pop) begin
                if (rd_ptr == PTR_WIDTH'(DEPTH - 1)) begin
                    rd_ptr <= '0;
                end else begin
                    rd_ptr <= rd_ptr + 1'b1;
                end
            end
            case (transfers)
                2'b10: occupancy <= occupancy + 1'b1;
                2'b01: occupancy <= occupancy - 1'b1;
                default: occupancy <= occupancy;
            endcase
        end
    end
`ifndef SYNTHESIS
    initial begin
        if (DATA_WIDTH == 0 || DEPTH == 0) begin
            $fatal(1, "PARAM: buffer width/depth positive");
        end
        if (COUNT_WIDTH < $clog2(64'(DEPTH) + 64'd1) || COUNT_WIDTH == 0) begin
            $fatal(1, "PARAM: buffer occupancy width too small");
        end
    end
`endif

endmodule
`default_nettype wire
