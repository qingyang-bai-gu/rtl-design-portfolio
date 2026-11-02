`timescale 1ns/1ps
`default_nettype none

module tb_fir64;
    parameter integer FIFO_ADDR_BITS = 3;
    parameter COEFF_FILE = "coefficients/lowpass_q15.hex";
    reg arst_n = 1;
    reg sample_clk = 0, proc_clk = 0;
    integer sample_half = 7, proc_half = 5, phase = 2;
    reg signed [15:0] s_data = 0;
    reg s_valid = 0, m_ready = 0;
    wire s_ready, m_valid;
    wire signed [15:0] m_data;
    wire signed [37:0] m_acc;
    fir64_shared_mac #(.FIFO_ADDR_BITS(FIFO_ADDR_BITS), .COEFF_FILE(COEFF_FILE)) dut (.*);

    reg [15:0] inputs [0:8191];
    reg [15:0] expected [0:8191];
    reg [37:0] expected_acc [0:8191];
    integer count, sent = 0, received = 0, cycles = 0, start_cycle = 0;
    integer input_stalls = 0, output_stalls = 0, computations = 0;
    integer limit = 0, ready_mode = 0;
    reg checking = 0;
    reg held = 0;
    reg [15:0] held_data;
    reg [37:0] held_acc;
    reg [31:0] source_rng = 32'hc001cafe, sink_rng = 32'h12345678;
    string profile = "lowpass", dump_path;

    function automatic [31:0] step_rng(input [31:0] old);
        reg [31:0] v;
        begin
            v = old ^ (old << 13); v = v ^ (v >> 17); v = v ^ (v << 5);
            step_rng = v;
        end
    endfunction

    initial begin
        if ($value$plusargs("SAMPLE_HALF=%d", sample_half)) begin end
        forever #(sample_half) sample_clk = !sample_clk;
    end
    initial begin
        if ($value$plusargs("PROC_HALF=%d", proc_half)) begin end
        if ($value$plusargs("PHASE=%d", phase)) begin end
        #(phase);
        forever #(proc_half) proc_clk = !proc_clk;
    end
    initial begin
        if ($value$plusargs("VCD=%s", dump_path)) begin
            $dumpfile(dump_path);
            $dumpvars(0, dut);
        end
    end

    // Drive away from active edges and hold data/valid through every stall.
    task automatic send_vectors(input integer number);
        integer i, gaps;
        begin
            for (i = 0; i < number; i = i + 1) begin
                source_rng = step_rng(source_rng);
                gaps = source_rng[1:0];
                repeat (gaps) @(negedge sample_clk);
                @(negedge sample_clk);
                s_data = inputs[i]; s_valid = 1;
                @(posedge sample_clk);
                while (!s_ready) @(posedge sample_clk);
                @(negedge sample_clk); s_valid = 0;
            end
        end
    endtask

    task automatic reset_design;
        begin
            #1; arst_n = 0;
            s_valid = 0;
            repeat (4) @(negedge sample_clk);
            repeat (4) @(negedge proc_clk);
            #1; arst_n = 1;
            repeat (4) @(negedge proc_clk);
        end
    endtask

    always @(negedge proc_clk) begin
        sink_rng = step_rng(sink_rng);
        if (!arst_n || ready_mode == 0) m_ready = 0;
        else if (ready_mode == 2) m_ready = 1;
        else m_ready = (cycles % 1024 >= 180) && (sink_rng[2:0] != 0);
    end

    always @(posedge sample_clk or negedge arst_n) begin
        if (!arst_n) begin sent = 0; input_stalls = 0; end
        else begin
            if (s_valid && s_ready) sent = sent + 1;
            if (s_valid && !s_ready) input_stalls = input_stalls + 1;
        end
    end

    always @(posedge proc_clk or negedge arst_n) begin
        if (!arst_n) begin
            received = 0; cycles = 0; held = 0;
            output_stalls = 0; computations = 0;
        end else begin
            cycles = cycles + 1;
            if (held && (m_valid !== 1'b1 || m_data !== held_data || m_acc !== held_acc))
                $fatal(1, "Output changed under backpressure");
            held = m_valid && !m_ready;
            held_data = m_data; held_acc = m_acc;
            if (held) output_stalls = output_stalls + 1;
`ifndef GATE_SIM
            if (dut.take_sample) start_cycle = cycles;
            if (dut.state == 2 && dut.tap_index == 63) begin
                if (cycles - start_cycle != 65) $fatal(1, "Incorrect MAC sequencing latency");
                computations = computations + 1;
            end
            if (dut.take_sample && dut.mem_rd_en) $fatal(1, "SRAM read/write collision");
`endif
            if (checking && m_valid && m_ready) begin
                if (received >= limit || received >= sent) $fatal(1, "Unexpected output");
                if (m_data !== expected[received] || m_acc !== expected_acc[received])
                    $fatal(1, "Mismatch %s[%0d]: y=%0d expected=%0d acc=%0d expected_acc=%0d",
                        profile, received, m_data, $signed(expected[received]),
                        m_acc, $signed(expected_acc[received]));
                received = received + 1;
            end
        end
    end

    initial begin : test
        if (!$value$plusargs("COUNT=%d", count)) $fatal(1, "COUNT is required");
        if ($value$plusargs("PROFILE=%s", profile)) begin end
        if (count < 128 || count > 8192) $fatal(1, "Unsupported vector count");
        $readmemh("vectors/input.hex", inputs, 0, count-1);
        $readmemh($sformatf("vectors/%s_output.hex", profile), expected, 0, count-1);
        $readmemh($sformatf("vectors/%s_acc.hex", profile), expected_acc, 0, count-1);
        reset_design();

        // Abandon a partially accumulated sample with queued FIFO entries.
        ready_mode = 2;
        send_vectors(4);
`ifndef GATE_SIM
        wait (dut.state == 2 && dut.tap_index >= 8);
`else
        repeat (12) @(negedge proc_clk);
`endif
        reset_design();
        checking = 1; ready_mode = 1; limit = count;
        send_vectors(count);
        wait (received == count);
        repeat (90) @(negedge proc_clk);
`ifndef GATE_SIM
        if (computations != count) $fatal(1, "Missing/duplicate computation");
`endif
        if (output_stalls == 0) $fatal(1, "No output backpressure exercised");
        $display("PASS FIR profile=%s depth=%0d samples=%0d cycles=%0d input_stalls=%0d output_stalls=%0d",
            profile, 1 << FIFO_ADDR_BITS, count, cycles, input_stalls, output_stalls);

        // Reset a stalled output, then check startup against stale SRAM contents.
        checking = 0; ready_mode = 0;
        send_vectors(1);
        wait (m_valid);
        repeat (5) @(negedge proc_clk);
        reset_design();
        checking = 1; ready_mode = 2; limit = 128;
        send_vectors(128);
        wait (received == 128);
        repeat (90) @(negedge proc_clk);
`ifndef GATE_SIM
        if (computations != 128) $fatal(1, "Reset recovery failed");
`endif
        $display("PASS FIR reset recovery, 128 samples");
        $finish;
    end

    initial begin
        #100000000;
        $fatal(1, "FIR watchdog expired (sent=%0d received=%0d)", sent, received);
    end
endmodule

`default_nettype wire
