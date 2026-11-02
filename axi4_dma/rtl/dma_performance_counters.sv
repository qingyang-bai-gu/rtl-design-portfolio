`default_nettype none
// AXI-domain telemetry. Counters wrap modulo 2**COUNTER_WIDTH; stall counts can overlap.
module dma_performance_counters #(
    parameter int unsigned COUNTER_WIDTH = 64,
    localparam int unsigned COUNTER_BITS = COUNTER_WIDTH == 0 ? 1 : COUNTER_WIDTH
) (
    input logic clk,
    input logic rst_n,
    input logic busy,
    input logic start_event,
    input logic finish_event,
    input logic [1:0] finish_status,
    input logic arvalid,
    input logic arready,
    input logic rvalid,
    input logic rready,
    input logic awvalid,
    input logic awready,
    input logic wvalid,
    input logic wready,
    input logic bvalid,
    input logic bready,
    output logic [COUNTER_BITS-1:0] cycle_count,
    output logic [COUNTER_BITS-1:0] active_cycle_count,
    output logic [COUNTER_BITS-1:0] descriptor_count,
    output logic [COUNTER_BITS-1:0] completion_count,
    output logic [COUNTER_BITS-1:0] error_count,
    output logic [COUNTER_BITS-1:0] read_burst_count,
    output logic [COUNTER_BITS-1:0] read_beat_count,
    output logic [COUNTER_BITS-1:0] write_burst_count,
    output logic [COUNTER_BITS-1:0] write_beat_count,
    output logic [COUNTER_BITS-1:0] write_response_count,
    output logic [COUNTER_BITS-1:0] ar_stall_count,
    output logic [COUNTER_BITS-1:0] r_stall_count,
    output logic [COUNTER_BITS-1:0] aw_stall_count,
    output logic [COUNTER_BITS-1:0] w_stall_count,
    output logic [COUNTER_BITS-1:0] b_stall_count
);
    timeunit 1ns / 1ps;
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            cycle_count <= '0;
            active_cycle_count <= '0;
            descriptor_count <= '0;
            completion_count <= '0;
            error_count <= '0;
            read_burst_count <= '0;
            read_beat_count <= '0;
            write_burst_count <= '0;
            write_beat_count <= '0;
            write_response_count <= '0;
            ar_stall_count <= '0;
            r_stall_count <= '0;
            aw_stall_count <= '0;
            w_stall_count <= '0;
            b_stall_count <= '0;
        end else begin
            cycle_count <= cycle_count + COUNTER_BITS'(1'b1);
            active_cycle_count <= active_cycle_count + COUNTER_BITS'(busy);
            descriptor_count <= descriptor_count + COUNTER_BITS'(start_event);
            completion_count <= completion_count + COUNTER_BITS'(finish_event);
            error_count <= error_count + COUNTER_BITS'(finish_event && finish_status != 2'b00);
            read_burst_count <= read_burst_count + COUNTER_BITS'(arvalid && arready);
            read_beat_count <= read_beat_count + COUNTER_BITS'(rvalid && rready);
            write_burst_count <= write_burst_count + COUNTER_BITS'(awvalid && awready);
            write_beat_count <= write_beat_count + COUNTER_BITS'(wvalid && wready);
            write_response_count <= write_response_count + COUNTER_BITS'(bvalid && bready);
            ar_stall_count <= ar_stall_count + COUNTER_BITS'(arvalid && !arready);
            r_stall_count <= r_stall_count + COUNTER_BITS'(rvalid && !rready);
            aw_stall_count <= aw_stall_count + COUNTER_BITS'(awvalid && !awready);
            w_stall_count <= w_stall_count + COUNTER_BITS'(wvalid && !wready);
            b_stall_count <= b_stall_count + COUNTER_BITS'(bvalid && !bready);
        end
    end
`ifndef SYNTHESIS
    initial begin
        if (COUNTER_WIDTH == 0) begin
            $fatal(1, "PARAM: COUNTER_WIDTH must be positive");
        end
    end
`endif
endmodule
`default_nettype wire
