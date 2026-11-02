`timescale 1ns/1ps
`default_nettype none

// Self-contained regression: no images, Python model, or external libraries.
// From the risc3_pipeline directory:
//   iverilog -g2012 -Wall -s tb_risc3 -o /tmp/risc3_sim rtl/risc3_core.v tb/tb_risc3.sv
//   vvp /tmp/risc3_sim
// Add +VCD=/tmp/risc3.vcd to record the regression waveform.
// The sequential oracle below has no pipeline or bypass state. Every retirement
// field, final memory word, and total pipeline cycle count is checked.
module tb_risc3;
    localparam integer IMEM_WORDS = 1024;
    localparam integer DMEM_WORDS = 256;
    localparam integer MAX_COMMITS = 8192;

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

    reg [31:0] instructions [0:IMEM_WORDS-1];
    reg [31:0] memory [0:DMEM_WORDS-1];
    reg [31:0] expected_memory [0:DMEM_WORDS-1];
    reg [31:0] model_regs [0:15];
    assign imem_rdata = (imem_addr < 4 * IMEM_WORDS) ?
                       instructions[imem_addr[11:2]] : 32'hffffffff;
    assign dmem_rdata = (dmem_raddr < 4 * DMEM_WORDS) ?
                       memory[dmem_raddr[9:2]] : 32'hxxxxxxxx;

    typedef struct packed {
        reg [31:0] pc, insn;
        reg reg_we;
        reg [3:0] rd;
        reg [31:0] data;
        reg store;
        reg [31:0] addr, store_data;
        reg [1:0] fault;
        reg stop;
    } commit_t;
    commit_t expected_trace [0:MAX_COMMITS-1];
    commit_t expected_event, actual_event;
    integer image_words, expected_count, expected_cycles, expected_fault;
    integer cycles = 0, commits = 0;
    integer total_cases = 0, total_commits = 0, total_cycles = 0;
    integer opcode_hits [0:15];
    integer fault_hits [0:3];
    integer i, j, seed;
    string case_name, dump_file;
    reg [31:0] random_state;

    function automatic [31:0] rr(input integer op, d, a, b);
        rr = (op << 28) | (d << 24) | (a << 20) | (b << 16);
    endfunction
    function automatic [31:0] ri(input integer op, d, a, value);
        ri = (op << 28) | (d << 24) | (a << 20) | (value & 65535);
    endfunction
    function automatic [31:0] branch(input integer ne, a, b, displacement);
        branch = rr(13, ne, a, b) | (displacement & 65535);
    endfunction
    function automatic [31:0] jump(input integer d, displacement);
        jump = (14 << 28) | (d << 24) | (displacement & 24'hffffff);
    endfunction
    function automatic [31:0] invalid_word(input integer index);
        case (index)
            0: invalid_word = 32'h00000001;
            1: invalid_word = 32'h11000001;
            2: invalid_word = 32'h2100ffff;
            3: invalid_word = 32'h31000001;
            4: invalid_word = 32'h41000001;
            5: invalid_word = 32'h51000001;
            6: invalid_word = 32'h61000001;
            7: invalid_word = 32'h71000001;
            8: invalid_word = 32'h81000001;
            9: invalid_word = 32'h91010000;
            10: invalid_word = 32'ha1010000;
            11: invalid_word = 32'hb1010001;
            12: invalid_word = 32'hc1010001;
            13: invalid_word = 32'hd2000000;
            default: invalid_word = 32'hf0000001;
        endcase
    endfunction
    function integer choose(input integer bound);
        // Fixed local generator, so a failing seed reproduces the same image.
        random_state = random_state * 32'h9e3779b1 + 32'h7f4a7c15;
        choose = (random_state >> 1) % bound;
    endfunction

    task automatic emit(input reg [31:0] word);
        if (image_words >= IMEM_WORDS) $fatal(1, "test image too large");
        instructions[image_words] = word;
        image_words = image_words + 1;
    endtask

    task automatic begin_case(input string name);
        integer n;
        @(negedge clk);
        rst = 1;
        case_name = name;
        image_words = 0;
        for (n = 0; n < IMEM_WORDS; n = n + 1)
            instructions[n] = 32'hffffffff;
        for (n = 0; n < DMEM_WORDS; n = n + 1) begin
            memory[n] = (n * 32'h10203) ^ 32'ha5a50000;
            expected_memory[n] = memory[n];
        end
    endtask

    task automatic build_reference;
        commit_t event_record;
        reg [31:0] pc, next_pc, word, value, address;
        reg signed [31:0] offset;
        reg legal, writes_register, done;
        integer op, d, a, b, n, taken;
        begin
            for (n = 0; n < 16; n = n + 1) model_regs[n] = 0;
            pc = 0;
            done = 0;
            taken = 0;
            expected_count = 0;
            while (!done && expected_count < MAX_COMMITS) begin
                if (pc[1:0] != 0 || pc / 4 >= image_words)
                    $fatal(1, "%s: reference PC outside image: %h", case_name, pc);
                word = instructions[pc / 4];
                op = word[31:28];
                d = word[27:24];
                a = word[23:20];
                b = word[19:16];
                offset = {{16{word[15]}}, word[15:0]};
                next_pc = pc + 4;
                value = 0;
                writes_register = 0;
                legal = 1;
                event_record = '0;
                event_record.pc = pc;
                event_record.insn = word;
                case (op)
                    0: legal = (word == 0);
                    1, 2, 3, 4, 5, 6, 7, 8: begin
                        legal = (word[15:0] == 0);
                        writes_register = 1;
                        case (op)
                            1: value = model_regs[a] + model_regs[b];
                            2: value = model_regs[a] - model_regs[b];
                            3: value = model_regs[a] & model_regs[b];
                            4: value = model_regs[a] | model_regs[b];
                            5: value = model_regs[a] ^ model_regs[b];
                            6: value = ($signed(model_regs[a]) < $signed(model_regs[b]));
                            7: value = model_regs[a] << (model_regs[b] % 32);
                            8: value = model_regs[a] >> (model_regs[b] % 32);
                        endcase
                    end
                    9: begin
                        legal = (b == 0);
                        writes_register = 1;
                        value = model_regs[a] + offset;
                    end
                    10: begin
                        legal = (word[23:16] == 0);
                        writes_register = 1;
                        value = {word[15:0], 16'b0};
                    end
                    11, 12: begin
                        legal = (b == 0);
                        address = model_regs[a] + offset;
                        if (address % 4 != 0) begin
                            event_record.fault = (op == 11) ? 2 : 3;
                            event_record.stop = 1;
                        end else if (legal) begin
                            if (address / 4 >= DMEM_WORDS)
                                $fatal(1, "%s: reference data address outside memory", case_name);
                            if (op == 11) begin
                                writes_register = 1;
                                value = expected_memory[address / 4];
                            end else begin
                                event_record.store = 1;
                                event_record.addr = address;
                                event_record.store_data = model_regs[d];
                            end
                        end
                    end
                    13: begin
                        legal = (d == 0 || d == 1);
                        if (legal && ((model_regs[a] == model_regs[b]) == (d == 0))) begin
                            next_pc = pc + 4 + offset * 4;
                            taken = taken + 1;
                        end
                    end
                    14: begin
                        writes_register = 1;
                        value = pc + 4;
                        offset = {{8{word[23]}}, word[23:0]};
                        next_pc = pc + 4 + offset * 4;
                        taken = taken + 1;
                    end
                    15: begin
                        legal = (word == 32'hf0000000);
                        event_record.stop = 1;
                    end
                endcase
                if (!legal) begin
                    event_record.fault = 1;
                    event_record.stop = 1;
                    event_record.store = 0;
                    writes_register = 0;
                end
                if (writes_register && d != 0 && event_record.fault == 0) begin
                    event_record.reg_we = 1;
                    event_record.rd = d[3:0];
                    event_record.data = value;
                    model_regs[d] = value;
                end
                if (event_record.store)
                    expected_memory[event_record.addr / 4] = event_record.store_data;
                expected_trace[expected_count] = event_record;
                expected_count = expected_count + 1;
                done = event_record.stop;
                pc = next_pc;
            end
            if (!done) $fatal(1, "%s: reference execution limit", case_name);
            expected_cycles = expected_count + taken + 2;
            expected_fault = event_record.fault;
        end
    endtask

    task automatic run_case;
        integer n;
        begin
            build_reference();
            repeat (2) @(negedge clk);
            rst = 0;
            while (!halted) @(negedge clk);
            repeat (4) @(negedge clk);
            if (commits != expected_count || fault !== expected_fault[1:0])
                $fatal(1, "%s: final commit count or fault mismatch", case_name);
            for (n = 0; n < DMEM_WORDS; n = n + 1)
                if (memory[n] !== expected_memory[n])
                    $fatal(1, "%s: memory mismatch at word %0d", case_name, n);
            total_cases = total_cases + 1;
            total_cycles = total_cycles + expected_cycles;
        end
    endtask

    always @(posedge clk) begin
        if (rst) begin
            cycles = 0;
            commits = 0;
            if (retire_valid || dmem_we || dmem_re)
                $fatal(1, "side effect during reset");
        end else begin
            cycles = cycles + 1;
            if (cycles > expected_cycles + 8)
                $fatal(1, "%s: timeout at PC %h", case_name, imem_addr);
            if (dmem_re && (dmem_raddr >= 4 * DMEM_WORDS || dmem_raddr[1:0] != 0))
                $fatal(1, "%s: invalid read %h", case_name, dmem_raddr);
            if (dmem_we) begin
                if (!retire_valid || !retire_store || dmem_waddr >= 4 * DMEM_WORDS || dmem_waddr[1:0] != 0)
                    $fatal(1, "%s: invalid write", case_name);
                memory[dmem_waddr[9:2]] <= dmem_wdata;
            end
            if (retire_valid) begin
                if (halted || commits >= expected_count)
                    $fatal(1, "%s: extra retirement", case_name);
                actual_event = {retire_pc, retire_insn, retire_reg_we, retire_rd, retire_data,
                                retire_store, retire_addr, retire_store_data, retire_fault, retire_stop};
                expected_event = expected_trace[commits];
                if (actual_event !== expected_event) begin
                    $display("expected pc=%h insn=%h we=%b rd=%h data=%h store=%b addr=%h value=%h fault=%h stop=%b",
                             expected_event.pc, expected_event.insn, expected_event.reg_we,
                             expected_event.rd, expected_event.data, expected_event.store,
                             expected_event.addr, expected_event.store_data, expected_event.fault, expected_event.stop);
                    $display("actual   pc=%h insn=%h we=%b rd=%h data=%h store=%b addr=%h value=%h fault=%h stop=%b",
                             retire_pc, retire_insn, retire_reg_we, retire_rd, retire_data,
                             retire_store, retire_addr, retire_store_data, retire_fault, retire_stop);
                    $fatal(1, "%s: mismatch at commit %0d cycle %0d", case_name, commits, cycles);
                end
                opcode_hits[retire_insn[31:28]] = opcode_hits[retire_insn[31:28]] + 1;
                fault_hits[retire_fault] = fault_hits[retire_fault] + 1;
                commits = commits + 1;
                total_commits = total_commits + 1;
                if (retire_stop && cycles != expected_cycles)
                    $fatal(1, "%s: expected %0d cycles, got %0d", case_name, expected_cycles, cycles);
            end
            if (halted && (dmem_we || dmem_re || retire_valid))
                $fatal(1, "%s: activity after halt", case_name);
        end
    end

    task automatic directed_test(input integer which);
        integer n;
        begin
            begin_case($sformatf("directed_%0d", which));
            case (which)
                0: begin // Sum 1..10, looping backward; store/load the known answer.
                    emit(ri(9,1,0,10)); emit(ri(9,2,0,0));
                    emit(rr(1,2,2,1)); emit(ri(9,1,1,-1)); emit(branch(1,1,0,-3));
                    emit(ri(12,2,0,0)); emit(ri(11,3,0,0)); emit(rr(2,4,3,2));
                    emit(branch(0,4,0,1)); emit(ri(12,1,0,4)); emit(32'hf0000000);
                end
                1: begin // Overflow, signed compare, bitwise ops, shift counts 0/31/32/33.
                    emit(ri(9,1,0,-1)); emit(ri(9,2,0,1)); emit(rr(1,3,1,2));
                    emit(rr(2,4,0,2)); emit(ri(10,5,0,16'h8000));
                    emit(rr(6,6,5,1)); emit(rr(6,7,1,5)); emit(rr(3,8,5,1));
                    emit(rr(4,9,5,2)); emit(rr(5,10,1,5)); emit(ri(9,11,0,31));
                    emit(rr(7,12,2,11)); emit(rr(8,13,12,11)); emit(ri(9,11,0,32));
                    emit(rr(7,12,2,11)); emit(ri(9,11,0,33)); emit(rr(8,13,1,11));
                    emit(ri(9,2,5,-1)); emit(ri(9,3,2,1)); emit(rr(7,4,3,0));
                    emit(ri(9,1,0,-32768)); emit(ri(9,2,1,32767)); emit(32'hf0000000);
                end
                2: begin // Forward both ALU operands, base addresses and store values.
                    emit(ri(9,1,0,4)); emit(rr(1,2,1,1)); emit(rr(2,3,2,1));
                    emit(ri(12,3,1,0)); emit(ri(11,4,1,0)); emit(rr(1,5,4,3));
                    emit(ri(12,5,0,8)); emit(ri(11,6,0,8)); emit(branch(0,6,5,1));
                    emit(ri(12,1,0,12)); emit(ri(9,7,6,1)); emit(32'hf0000000);
                    emit(ri(12,7,0,16));
                end
                3: begin // Writes to r0 are discarded, including loads and JAL.
                    emit(ri(9,0,0,9)); emit(rr(1,1,0,0)); emit(ri(10,0,0,65535));
                    emit(ri(11,0,0,0)); emit(jump(0,1)); emit(ri(12,0,0,0));
                    emit(ri(12,0,0,4)); emit(ri(11,2,0,4)); emit(32'hf0000000);
                end
                4: begin // Taken/untaken paths, link address, skipped illegal/store.
                    emit(ri(9,1,0,1)); emit(branch(0,1,0,2)); emit(branch(1,1,1,1));
                    emit(branch(1,1,0,1)); emit(32'hffffffff); emit(jump(2,1));
                    emit(ri(12,1,0,0)); emit(ri(9,3,2,-24)); emit(branch(0,3,0,1));
                    emit(32'hffffffff); emit(32'hf0000000);
                end
                5: begin // Negative JAL displacement and link use at its target.
                    emit(jump(0,2)); emit(ri(12,3,0,0)); emit(32'hf0000000);
                    emit(jump(3,-3)); emit(ri(12,0,0,0));
                end
                6: begin // Store-to-load forwarding, nonalias read, negative offset.
                    emit(ri(10,1,0,16'h1234)); emit(ri(9,1,1,16'h5678));
                    emit(ri(12,1,0,0)); emit(ri(11,2,0,0)); emit(ri(12,2,0,4));
                    emit(ri(11,3,0,0)); emit(ri(9,4,0,8)); emit(ri(12,3,4,-4));
                    emit(ri(11,5,4,-4)); emit(ri(11,6,0,1020)); emit(32'hf0000000);
                end
                7, 8: begin // A flushed HALT or fault must not stop the branch target.
                    emit(branch(0,0,0,1));
                    emit((which == 7) ? 32'hf0000000 : 32'hffffffff);
                    emit(ri(9,1,0,5)); emit(32'hf0000000);
                end
                9: begin emit(32'hf0000000); emit(ri(12,1,0,0)); end
                10: begin
                    for (n = 0; n < 24; n = n + 1) emit(0);
                    emit(32'hf0000000);
                end
                11: begin // Every register index, plus consecutive writes to one rd.
                    for (n = 1; n < 16; n = n + 1) emit(ri(9,n,0,n));
                    for (n = 15; n > 0; n = n - 1) emit(rr(1,1,1,n));
                    emit(ri(9,2,0,8)); emit(ri(9,2,0,9)); emit(rr(1,3,2,2));
                    emit(32'hf0000000);
                end
            endcase
            run_case();
            if (which == 0 && memory[0] !== 32'd55) $fatal(1, "sum must equal 55");
        end
    endtask

    task automatic random_test(input integer test_seed);
        integer n, kind, d, a, b, op, displacement, immediate;
        begin
            begin_case($sformatf("random_%0d", test_seed));
            random_state = 32'h5a1d2e39 ^ test_seed;
            emit(ri(9,14,0,0)); // Keep r14 as a safe data-memory base.
            for (n = 1; n < 14; n = n + 1) begin
                immediate = choose(65536); emit(ri(10,n,0,immediate));
                immediate = choose(65536) - 32768; emit(ri(9,n,n,immediate));
            end
            for (n = 0; n < 240; n = n + 1) begin
                kind = choose(12); d = choose(14); a = choose(14); b = choose(14);
                case (kind)
                    0, 1, 2, 3, 4: begin op = 1 + choose(8); emit(rr(op,d,a,b)); end
                    5: begin immediate = choose(65536) - 32768; emit(ri(9,d,a,immediate)); end
                    6: begin immediate = choose(65536); emit(ri(10,d,0,immediate)); end
                    7, 8: begin immediate = 4 * choose(16); emit(ri((kind == 7) ? 11 : 12,d,14,immediate)); end
                    9: begin
                        op = choose(2); displacement = choose(4);
                        emit(branch(op,a,b,displacement));
                    end
                    10: begin displacement = choose(3); emit(jump(d,displacement)); end
                    11: emit(0);
                endcase
            end
            repeat (4) emit(0); // Forward branches near the image end land safely.
            emit(32'hf0000000); emit(ri(12,1,14,0));
            run_case();
        end
    endtask

    initial begin
        for (i = 0; i < 16; i = i + 1) opcode_hits[i] = 0;
        for (i = 0; i < 4; i = i + 1) fault_hits[i] = 0;
        if ($value$plusargs("VCD=%s", dump_file)) begin
            $dumpfile(dump_file);
            $dumpvars(0, dut);
        end
        for (i = 0; i < 12; i = i + 1) directed_test(i);
        for (i = 0; i < 15; i = i + 1) begin
            begin_case($sformatf("illegal_%0d", i));
            emit(ri(9,1,0,17)); emit(invalid_word(i)); emit(ri(12,1,0,0)); emit(32'hf0000000);
            run_case();
        end
        for (i = 11; i <= 12; i = i + 1)
            for (j = 1; j <= 4; j = j + 1) begin
                begin_case($sformatf("unaligned_op%0d_offset%0d", i, j));
                emit(ri(9,1,0,9)); emit(ri(12,1,0,0));
                emit(ri(i,1,0,(j == 4) ? -1 : j)); emit(ri(12,1,0,4)); emit(32'hf0000000);
                run_case();
            end
        for (seed = 0; seed < 40; seed = seed + 1) random_test(seed);
        for (i = 0; i < 16; i = i + 1)
            if (opcode_hits[i] == 0) $fatal(1, "opcode %0h never retired", i);
        for (i = 1; i < 4; i = i + 1)
            if (fault_hits[i] == 0) $fatal(1, "fault %0d never tested", i);
        $display("PASS: %0d programs, %0d retirements, %0d execution cycles; all 16 opcodes and 3 faults exercised",
                 total_cases, total_commits, total_cycles);
        $finish;
    end
endmodule

`default_nettype wire
