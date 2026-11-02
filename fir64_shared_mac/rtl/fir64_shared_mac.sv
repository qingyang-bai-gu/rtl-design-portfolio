`timescale 1ns/1ps
`default_nettype none

// Signed 16-bit Q1.15 samples and coefficients. One shared 16x16 multiplier,
// one 38-bit accumulator, one output holding register in the processing domain.
module fir64_shared_mac #(
    parameter integer FIFO_ADDR_BITS = 3,
    parameter COEFF_FILE = "coefficients/lowpass_q15.hex"
) (
    input  wire               arst_n,
    input  wire               sample_clk,
    input  wire signed [15:0] s_data,
    input  wire               s_valid,
    output wire               s_ready,
    input  wire               proc_clk,
    output reg signed [15:0]  m_data,
    output reg signed [37:0]  m_acc,
    output reg                m_valid,
    input  wire               m_ready
);
    wire proc_rst_n;
    fir_reset_sync u_proc_reset (.clk(proc_clk), .arst_n(arst_n), .rst_n(proc_rst_n));

    wire [15:0] fifo_data;
    wire fifo_valid, fifo_ready;
    fir_async_fifo #(.WIDTH(16), .ADDR_BITS(FIFO_ADDR_BITS)) u_input_fifo (
        .arst_n(arst_n), .wr_clk(sample_clk), .wr_data(s_data),
        .wr_valid(s_valid), .wr_ready(s_ready), .rd_clk(proc_clk),
        .rd_data(fifo_data), .rd_valid(fifo_valid), .rd_ready(fifo_ready)
    );

    localparam [1:0] IDLE = 2'd0, PRIME = 2'd1, MAC = 2'd2;
    reg [1:0] state;
    reg [5:0] write_ptr, base_ptr, tap_index;
    reg [6:0] history_count;
    reg signed [37:0] accumulator;
    wire take_sample = fifo_valid && fifo_ready;
    assign fifo_ready = proc_rst_n && state == IDLE && (!m_valid || m_ready);

    // PRIME requests tap zero. Every MAC edge requests the following tap while
    // accumulating the prior synchronous memory responses.
    wire mem_rd_en = proc_rst_n && ((state == PRIME) || ((state == MAC) && tap_index != 63));
    wire [5:0] mem_tap = state == PRIME ? 6'd0 : tap_index + 6'd1;
    wire [5:0] sample_addr = base_ptr - mem_tap;
    wire signed [15:0] sample_q, coeff_q;
    fir_sample_sram u_history (
        .clk(proc_clk), .wr_en(take_sample), .wr_addr(write_ptr), .wr_data(fifo_data),
        .rd_en(mem_rd_en), .rd_addr(sample_addr), .rd_data(sample_q)
    );
    fir_coeff_rom #(.COEFF_FILE(COEFF_FILE)) u_coefficients (
        .clk(proc_clk), .rd_en(mem_rd_en), .rd_addr(mem_tap), .rd_data(coeff_q)
    );

    wire signed [31:0] product = sample_q * coeff_q;
    // A conditional, rather than multiplication by zero, masks unknown SRAM
    // contents during startup in four-state simulation as well as in hardware.
    wire signed [37:0] addend = ({1'b0, tap_index} < history_count)
        ? {{6{product[31]}}, product} : 38'sd0;
    wire signed [37:0] sum_next = accumulator + addend;

    // Round to nearest with half-way values away from zero; then saturate.
    function automatic signed [15:0] quantize;
        input signed [37:0] value;
        reg signed [38:0] wide_value, magnitude, rounded;
        begin
            wide_value = {value[37], value};
            magnitude = wide_value < 0 ? -wide_value : wide_value;
            rounded = (magnitude + 39'sd16384) >>> 15;
            if (wide_value < 0) rounded = -rounded;
            if      (rounded > 39'sd32767)  quantize = 16'sh7fff;
            else if (rounded < -39'sd32768) quantize = 16'sh8000;
            else                            quantize = rounded[15:0];
        end
    endfunction

    always @(posedge proc_clk or negedge proc_rst_n) begin
        if (!proc_rst_n) begin
            state <= IDLE;
            write_ptr <= 0;
            base_ptr <= 0;
            tap_index <= 0;
            history_count <= 0;
            accumulator <= 0;
            m_data <= 0;
            m_acc <= 0;
            m_valid <= 0;
        end else begin
            if (m_valid && m_ready) m_valid <= 0;
            case (state)
                IDLE: if (take_sample) begin
                    base_ptr <= write_ptr;
                    write_ptr <= write_ptr + 6'd1;
                    if (history_count < 64) history_count <= history_count + 7'd1;
                    accumulator <= 0;
                    tap_index <= 0;
                    state <= PRIME;
                end
                PRIME: state <= MAC;
                MAC: begin
                    accumulator <= sum_next;
                    if (tap_index == 63) begin
                        m_data <= quantize(sum_next);
                        m_acc <= sum_next;
                        m_valid <= 1;
                        state <= IDLE;
                    end else tap_index <= tap_index + 6'd1;
                end
                default: state <= IDLE;
            endcase
        end
    end
endmodule

`default_nettype wire
