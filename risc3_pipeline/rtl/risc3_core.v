`timescale 1ns/1ps
`default_nettype none

// R3: a project-specific 32-bit ISA, with 16 registers and hardwired r0 = 0.
// Three stages: capture an instruction, execute it, then retire its effects.
// Both memory read ports are combinational. All stores commit in writeback.
// Addresses are byte addresses; instructions and data transfers are 32 bits.
// The memory interface has no ready, wait-state, or bus-error signaling.
// A taken branch or JAL discards the incoming fetch and costs one cycle.
// Reset is synchronous, active high, and restarts execution at address zero.
//
// Encoding: op[31:28], rd[27:24], ra[23:20], rb[19:16], imm16[15:0].
//   0 NOP: the whole instruction must be zero.
//   1 ADD, 2 SUB, 3 AND, 4 OR, 5 XOR, 6 signed SLT, 7 SHL, 8 logical SHR:
//     rd <- ra op rb; imm16 must be zero; shift counts use rb[4:0].
//   9 ADDI: rd <- ra + sign_extend(imm16); rb must be zero.
//   A LUI: rd <- imm16 << 16; bits [23:16] must be zero.
//   B LD: rd <- mem[ra + sign_extend(imm16)]; rb must be zero.
//   C ST: mem[ra + sign_extend(imm16)] <- rd; rb must be zero.
//   D BR: rd is the condition (0 BEQ, 1 BNE); compare ra and rb.
//     target = PC + 4 + sign_extend(imm16)*4. Other conditions are illegal.
//   E JAL: rd <- PC + 4; target = PC + 4 + sign_extend(insn[23:0])*4.
//   F HALT: only 0xf0000000 is legal.
// Arithmetic and PC updates wrap to 32 bits. Reserved fields must be zero.
// Faults retire once and stop the core: 1 illegal, 2 unaligned LD, 3 unaligned ST.
// An illegal encoding takes precedence over alignment; faults have no side effects.
// HALT/fault preserve older commits and discard all younger instructions.
// Retirement outputs describe the writeback event sampled on the rising edge.
module risc3_core (
    input  wire        clk,
    input  wire        rst,
    output wire [31:0] imem_addr,
    input  wire [31:0] imem_rdata,
    output wire        dmem_re,
    output wire [31:0] dmem_raddr,
    input  wire [31:0] dmem_rdata,
    output wire        dmem_we,
    output wire [31:0] dmem_waddr,
    output wire [31:0] dmem_wdata,
    output reg         halted,
    output reg  [1:0]  fault,
    output wire        retire_valid,
    output wire [31:0] retire_pc,
    output wire [31:0] retire_insn,
    output wire        retire_reg_we,
    output wire [3:0]  retire_rd,
    output wire [31:0] retire_data,
    output wire        retire_store,
    output wire [31:0] retire_addr,
    output wire [31:0] retire_store_data,
    output wire [1:0]  retire_fault,
    output wire        retire_stop
);
    reg [31:0] regs [0:15];
    reg [31:0] fetch_pc;
    reg        fetch_stopped;
    reg        f_valid;
    reg [31:0] f_pc, f_insn;

    reg        w_valid, w_reg_we, w_store, w_stop;
    reg [3:0]  w_rd;
    reg [31:0] w_pc, w_insn, w_data, w_addr, w_store_data;
    reg [1:0]  w_fault;

    wire [3:0] op = f_insn[31:28];
    wire [3:0] rd = f_insn[27:24];
    wire [3:0] ra = f_insn[23:20];
    wire [3:0] rb = f_insn[19:16];
    wire [31:0] imm = {{16{f_insn[15]}}, f_insn[15:0]};
    wire wb_commit = w_valid && !halted && !rst;
    wire wb_write = wb_commit && w_reg_we && (w_rd != 0);

    // Read-through forwarding also supplies branch operands and store data.
    wire [31:0] a = (ra == 0) ? 32'b0 :
                         ((wb_write && w_rd == ra) ? w_data : regs[ra]);
    wire [31:0] b = (rb == 0) ? 32'b0 :
                         ((wb_write && w_rd == rb) ? w_data : regs[rb]);
    wire [31:0] store_value = (rd == 0) ? 32'b0 :
                         ((wb_write && w_rd == rd) ? w_data : regs[rd]);
    wire [31:0] effective_addr = a + imm;

    reg x_reg_we, x_store, x_stop, x_redirect;
    reg [31:0] x_data, x_target;
    reg [1:0] x_fault;
    reg legal;

    assign imem_addr = fetch_pc;
    assign dmem_raddr = effective_addr;
    assign dmem_re = f_valid && !fetch_stopped && !halted && !rst &&
                     op == 4'hb && rb == 0 && effective_addr[1:0] == 0;
    assign dmem_we = wb_commit && w_store;
    assign dmem_waddr = w_addr;
    assign dmem_wdata = w_store_data;

    assign retire_valid = wb_commit;
    assign retire_pc = w_pc;
    assign retire_insn = w_insn;
    assign retire_reg_we = wb_write;
    assign retire_rd = wb_write ? w_rd : 4'b0;
    assign retire_data = wb_write ? w_data : 32'b0;
    assign retire_store = dmem_we;
    assign retire_addr = dmem_we ? w_addr : 32'b0;
    assign retire_store_data = dmem_we ? w_store_data : 32'b0;
    assign retire_fault = w_fault;
    assign retire_stop = w_stop;

    always @* begin
        x_reg_we = 1'b0;
        x_store = 1'b0;
        x_stop = 1'b0;
        x_redirect = 1'b0;
        x_fault = 2'b0;
        x_data = 32'b0;
        x_target = 32'b0;
        legal = 1'b1;
        case (op)
            4'h0: legal = (f_insn == 0);
            4'h1, 4'h2, 4'h3, 4'h4, 4'h5, 4'h6, 4'h7, 4'h8: begin
                legal = (f_insn[15:0] == 0);
                x_reg_we = 1'b1;
                case (op)
                    4'h1: x_data = a + b;
                    4'h2: x_data = a - b;
                    4'h3: x_data = a & b;
                    4'h4: x_data = a | b;
                    4'h5: x_data = a ^ b;
                    4'h6: x_data = {31'b0, ($signed(a) < $signed(b))};
                    4'h7: x_data = a << b[4:0];
                    4'h8: x_data = a >> b[4:0];
                    default: x_data = 32'b0;
                endcase
            end
            4'h9: begin
                legal = (rb == 0);
                x_reg_we = 1'b1;
                x_data = a + imm;
            end
            4'ha: begin
                legal = (f_insn[23:16] == 0);
                x_reg_we = 1'b1;
                x_data = {f_insn[15:0], 16'b0};
            end
            4'hb, 4'hc: begin
                legal = (rb == 0);
                if (effective_addr[1:0] != 0) begin
                    x_fault = (op == 4'hb) ? 2'd2 : 2'd3;
                    x_stop = 1'b1;
                end else if (op == 4'hb) begin
                    x_reg_we = 1'b1;
                    // The memory array has not observed this cycle's WB store yet.
                    x_data = (dmem_we && w_addr == effective_addr) ?
                             w_store_data : dmem_rdata;
                end else begin
                    x_store = 1'b1;
                end
            end
            4'hd: begin
                legal = (rd == 0 || rd == 1);
                x_redirect = ((rd == 0) && (a == b)) ||
                             ((rd == 1) && (a != b));
                x_target = f_pc + 32'd4 + (imm << 2);
            end
            4'he: begin
                x_reg_we = 1'b1;
                x_data = f_pc + 32'd4;
                x_redirect = 1'b1;
                x_target = f_pc + 32'd4 +
                           {{6{f_insn[23]}}, f_insn[23:0], 2'b0};
            end
            4'hf: begin
                legal = (f_insn == 32'hf0000000);
                x_stop = 1'b1;
            end
            default: legal = 1'b0;
        endcase
        if (!legal) begin
            x_reg_we = 1'b0;
            x_store = 1'b0;
            x_redirect = 1'b0;
            x_fault = 2'd1;
            x_stop = 1'b1;
        end
    end

    integer i;
    always @(posedge clk) begin
        if (rst) begin
            fetch_pc <= 0;
            fetch_stopped <= 0;
            f_valid <= 0;
            f_pc <= 0;
            f_insn <= 0;
            w_valid <= 0;
            w_reg_we <= 0;
            w_store <= 0;
            w_stop <= 0;
            w_rd <= 0;
            w_pc <= 0;
            w_insn <= 0;
            w_data <= 0;
            w_addr <= 0;
            w_store_data <= 0;
            w_fault <= 0;
            halted <= 0;
            fault <= 0;
            for (i = 0; i < 16; i = i + 1)
                regs[i] <= 0;
        end else if (halted) begin
            f_valid <= 0;
            w_valid <= 0;
        end else begin
            if (wb_write)
                regs[w_rd] <= w_data;
            if (wb_commit && w_stop) begin
                halted <= 1;
                fault <= w_fault;
            end

            w_valid <= f_valid && !fetch_stopped;
            w_pc <= f_pc;
            w_insn <= f_insn;
            w_rd <= rd;
            w_reg_we <= x_reg_we && (rd != 0);
            w_data <= x_data;
            w_store <= x_store;
            w_addr <= effective_addr;
            w_store_data <= store_value;
            w_fault <= x_fault;
            w_stop <= x_stop;

            if (fetch_stopped) begin
                f_valid <= 0;
            end else if (f_valid && x_stop) begin
                fetch_stopped <= 1;
                f_valid <= 0;
            end else if (f_valid && x_redirect) begin
                fetch_pc <= x_target;
                f_valid <= 0;
            end else begin
                f_valid <= 1;
                f_pc <= fetch_pc;
                f_insn <= imem_rdata;
                fetch_pc <= fetch_pc + 32'd4;
            end
        end
    end
endmodule

`default_nettype wire
