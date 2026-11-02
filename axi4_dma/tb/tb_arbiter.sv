`default_nettype none
module tb_arbiter;
    timeunit 1ns / 1ps;
    parameter int unsigned REQUESTERS = 4;
    parameter bit WITHDRAW = 0;
    localparam int unsigned INDEX_WIDTH = REQUESTERS <= 1 ? 1 : $clog2(REQUESTERS);
    logic clk = 0;
    logic rst_n = 0;
    logic [REQUESTERS-1:0] request = '0;
    logic grant_ready = 0;
    logic grant_valid;
    logic [REQUESTERS-1:0] grant_onehot;
    logic [INDEX_WIDTH-1:0] grant_index;
    int unsigned priority_start = 0;
    int unsigned locked_index = 0;
    bit locked = 0;
    int unsigned expected_index;
    int unsigned distance;
    int unsigned best_distance;
    bit expected_valid;
    int unsigned accepted = 0;
    int unsigned served[REQUESTERS];
    logic [31:0] rng = 32'hA8B17E19;
    round_robin_arbiter #(
        .REQUESTERS(REQUESTERS)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .request(request),
        .grant_valid(grant_valid),
        .grant_onehot(grant_onehot),
        .grant_index(grant_index),
        .grant_ready(grant_ready)
    );
    rv_stability #(
        .WIDTH(REQUESTERS + INDEX_WIDTH)
    ) hold (
        .clk(clk),
        .rst_n(rst_n),
        .valid(grant_valid),
        .ready(grant_ready),
        .payload({grant_onehot, grant_index})
    );
    always begin
        #5;
        clk = !clk;
    end
    // Independent oracle ranks cyclic distances rather than duplicating the RTL scan.
    always @(posedge clk) begin
        if (!rst_n) begin
            priority_start = 0;
            locked = 0;
            accepted = 0;
            for (int i = 0; i < REQUESTERS; i = i + 1) begin
                served[i] = 0;
            end
        end else begin
            expected_valid = locked || (request != '0);
            expected_index = locked ? locked_index : 0;
            best_distance = REQUESTERS;
            if (!locked) begin
                for (int i = 0; i < REQUESTERS; i = i + 1) begin
                    distance = (i + REQUESTERS - priority_start) % REQUESTERS;
                    if (request[i] && distance < best_distance) begin
                        best_distance = distance;
                        expected_index = i;
                    end
                end
            end
            if (grant_valid !== expected_valid || grant_index !== INDEX_WIDTH'(expected_index) ||
                grant_onehot !== (expected_valid ? REQUESTERS'(1) << expected_index : '0)) begin
                $fatal(1, "arbiter N=%0d req=%b expected=%b/%0d got=%b/%0d/%b", REQUESTERS, request,
                       expected_valid, expected_index, grant_valid, grant_index, grant_onehot);
            end
            if (grant_valid && grant_ready) begin
                accepted = accepted + 1;
                served[expected_index] = served[expected_index] + 1;
                priority_start = (expected_index + 1) % REQUESTERS;
                locked = 0;
            end else if (grant_valid) begin
                locked = 1;
                locked_index = expected_index;
            end
        end
    end
    task automatic tick();
        @(posedge clk);
        #1;
        @(negedge clk);
    endtask
    initial begin
        #200000;
        $fatal(1, "arbiter watchdog");
    end
    initial begin
        @(negedge clk);
        tick();
        rst_n = 1;
        tick();
        request[REQUESTERS-1] = 1;
        tick();
        if (WITHDRAW) begin
            request = '0;
            tick();
            $fatal(1, "withdrawal was not diagnosed");
        end
        request = '1;
        repeat (4) begin
            tick();
        end
        grant_ready = 1;
        tick();
        request = '0;
        tick();
        rst_n = 0;
        tick();
        rst_n = 1;
        request = '1;
        for (int i = 0; i < REQUESTERS * 20; i = i + 1) begin
            tick();
        end
        for (int i = 0; i < REQUESTERS; i = i + 1) begin
            if (served[i] != 20) begin
                $fatal(1, "arbiter fairness N=%0d requester=%0d accepted=%0d", REQUESTERS, i,
                       served[i]);
            end
        end
        for (int i = 0; i < 4000; i = i + 1) begin
            for (int j = 0; j < REQUESTERS; j = j + 1) begin
                rng = rng ^ (rng << 13);
                rng = rng ^ (rng >> 17);
                rng = rng ^ (rng << 5);
                request[j] = rng[0];
            end
            if (locked) begin
                request[locked_index] = 1;
            end
            grant_ready = rng[3:1] != 0;
            tick();
        end
        rst_n = 0;
        #1;
        if (grant_valid || grant_onehot != 0 || grant_index != 0) begin
            $fatal(1, "arbiter reset suppression");
        end
        tick();
        rst_n = 1;
        request = '1;
        grant_ready = 1;
        repeat (REQUESTERS * 2) begin
            tick();
        end
        $display("PASS arbiter N=%0d seeded ownership/fairness/reset seed=A8B17E19", REQUESTERS);
        $finish;
    end
endmodule
`default_nettype wire
