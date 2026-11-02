`timescale 1ns/1ps
`default_nettype none

// Reset interruption and recovery, including reset while halted.
// From the risc3_pipeline directory:
//   iverilog -g2012 -Wall -s tb_reset -o /tmp/risc3_reset rtl/risc3_core.v tb/tb_reset.sv
//   vvp /tmp/risc3_reset
module tb_reset;
    reg clk = 0;
    always #5 clk = !clk;
    reg rst = 1;
    wire [31:0] imem_addr, imem_rdata;
    wire dmem_re, dmem_we, halted;
    wire [31:0] dmem_raddr, dmem_rdata, dmem_waddr, dmem_wdata;
    wire [1:0] fault, retire_fault;
    wire retire_valid, retire_reg_we, retire_store, retire_stop;
    wire [31:0] retire_pc, retire_insn, retire_data, retire_addr, retire_store_data;
    wire [3:0] retire_rd;
    risc3_core dut (.*);
    reg [31:0] memory = 0;
    reg [31:0] instruction;
    assign imem_rdata = instruction;
    assign dmem_rdata = memory;
    integer index = 0, phase, watchdog;
    reg [31:0] expected_data;
    always @* begin
        case (imem_addr)
            0: instruction = 32'h91100001; // ADDI r1,r1,1: detects incomplete register reset.
            4: instruction = 32'h92100002; // ADDI r2,r1,2
            8: instruction = 32'hc2000000; // ST r2,r0,0
            12: instruction = 32'hb3000000; // LD r3,r0,0
            16: instruction = 32'hf0000000;
            default: instruction = 32'hc1000000; // Must never retire after halt.
        endcase
    end
    always @(posedge clk) begin
        if (rst) begin
            index = 0;
            if (dmem_we || dmem_re || retire_valid) $fatal(1, "reset side effect");
            #1;
            if (halted || fault != 0 || imem_addr != 0) $fatal(1, "reset did not restart core");
        end else begin
            if (dmem_we) begin
                if (dmem_waddr != 0 || dmem_wdata != 3) $fatal(1, "wrong store after reset");
                memory <= dmem_wdata;
            end
            if (retire_valid) begin
                if (retire_pc != 4 * index || retire_fault != 0 || index > 4)
                    $fatal(1, "wrong instruction after reset");
                if (index == 0 || index == 1 || index == 3) begin
                    expected_data = (index == 0) ? 1 : 3;
                    if (!retire_reg_we || retire_rd != ((index == 3) ? 3 : index + 1) ||
                        retire_data != expected_data)
                        $fatal(1, "incorrect register reset or forwarding");
                end
                if (retire_stop != (index == 4) || retire_store != (index == 2))
                    $fatal(1, "wrong side effect after reset");
                index = index + 1;
            end
            if (halted && (retire_valid || dmem_we || dmem_re)) $fatal(1, "post-halt activity");
        end
    end
    initial begin
        repeat (2) @(negedge clk);
        for (phase = 1; phase <= 8; phase = phase + 1) begin
            rst = 0;
            repeat (phase) @(negedge clk);
            rst = 1;
            repeat (2) @(negedge clk);
        end
        rst = 0;
        watchdog = 0;
        while (!halted && watchdog < 20) begin
            @(negedge clk);
            watchdog = watchdog + 1;
        end
        if (!halted || index != 5 || fault != 0 || memory != 3) $fatal(1, "reset recovery failed");
        repeat (4) @(negedge clk);
        $display("PASS reset: eight interruption points and recovery");
        $finish;
    end
endmodule

`default_nettype wire
