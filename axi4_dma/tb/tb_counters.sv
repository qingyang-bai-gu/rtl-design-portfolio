`default_nettype none
module tb_counters;
    timeunit 1ns / 1ps;
    parameter int unsigned COUNTER_WIDTH = 4;
    logic clk = 0;
    logic rst_n = 0;
    logic busy = 0;
    logic start_event = 0;
    logic finish_event = 0;
    logic [1:0] finish_status = 0;
    logic [4:0] valid_bus = 0;
    logic [4:0] ready_bus = 0;
    logic [31:0] rng = 32'h418F007D;
    logic [COUNTER_WIDTH-1:0] observed[15];
    int expected[15];
    always begin
        #5;
        clk = !clk;
    end
    dma_performance_counters #(
        .COUNTER_WIDTH(COUNTER_WIDTH)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .busy(busy),
        .start_event(start_event),
        .finish_event(finish_event),
        .finish_status(finish_status),
        .arvalid(valid_bus[0]),
        .arready(ready_bus[0]),
        .rvalid(valid_bus[1]),
        .rready(ready_bus[1]),
        .awvalid(valid_bus[2]),
        .awready(ready_bus[2]),
        .wvalid(valid_bus[3]),
        .wready(ready_bus[3]),
        .bvalid(valid_bus[4]),
        .bready(ready_bus[4]),
        .cycle_count(observed[0]),
        .active_cycle_count(observed[1]),
        .descriptor_count(observed[2]),
        .completion_count(observed[3]),
        .error_count(observed[4]),
        .read_burst_count(observed[5]),
        .read_beat_count(observed[6]),
        .write_burst_count(observed[7]),
        .write_beat_count(observed[8]),
        .write_response_count(observed[9]),
        .ar_stall_count(observed[10]),
        .r_stall_count(observed[11]),
        .aw_stall_count(observed[12]),
        .w_stall_count(observed[13]),
        .b_stall_count(observed[14])
    );
    // Independent integer totals are truncated only at the comparison boundary.
    always @(posedge clk) begin
        if (!rst_n) begin
            for (int i = 0; i < 15; i = i + 1) begin
                expected[i] = 0;
            end
        end else begin
            expected[0] = expected[0] + 1;
            if (busy) begin
                expected[1] = expected[1] + 1;
            end
            if (start_event) begin
                expected[2] = expected[2] + 1;
            end
            if (finish_event) begin
                expected[3] = expected[3] + 1;
                if (finish_status != 0) begin
                    expected[4] = expected[4] + 1;
                end
            end
            for (int i = 0; i < 5; i = i + 1) begin
                if (valid_bus[i]) begin
                    if (ready_bus[i]) begin
                        expected[5+i] = expected[5+i] + 1;
                    end else begin
                        expected[10+i] = expected[10+i] + 1;
                    end
                end
            end
        end
        #0.1;
        for (int i = 0; i < 15; i = i + 1) begin
            if (observed[i] !== COUNTER_WIDTH'(expected[i])) begin
                $fatal(1, "counter index=%0d got=%0d expected=%0d", i, observed[i], expected[i]);
            end
        end
    end
    initial begin
        repeat (2) begin
            @(negedge clk);
        end
        rst_n = 1;
        for (int cycle = 0; cycle < 4096; cycle = cycle + 1) begin
            @(negedge clk);
            rng = rng ^ (rng << 13);
            rng = rng ^ (rng >> 17);
            rng = rng ^ (rng << 5);
            {finish_status, busy, start_event, finish_event, valid_bus, ready_bus} = 15'(rng);
            if (cycle < 64) begin
                busy = 1;
                start_event = 1;
                finish_event = 1;
                finish_status = 2;
                valid_bus = '1;
                ready_bus = 5'(cycle);
            end
            rst_n = cycle != 1000 && cycle != 1001;
        end
        @(negedge clk);
        $display("PASS counters width=%0d simultaneous events, wrap, reset", COUNTER_WIDTH);
        $finish;
    end
endmodule
`default_nettype wire
