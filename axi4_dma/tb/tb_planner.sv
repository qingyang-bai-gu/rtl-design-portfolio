`default_nettype none
module tb_planner;
    timeunit 1ns / 1ps;

    parameter int unsigned ADDR_WIDTH = 32;
    parameter int unsigned DATA_WIDTH = 128;
    parameter int unsigned MAX_BURST_BEATS = 16;
    localparam int unsigned BB = DATA_WIDTH / 8;
    logic [ADDR_WIDTH-1:0] src_addr;
    logic [ADDR_WIDTH-1:0] dst_addr;
    logic [ADDR_WIDTH:0] remaining_bytes;
    logic plan_valid;
    logic [8:0] plan_beats;
    logic [12:0] plan_bytes;
    integer fd;
    integer rc;
    integer expected;
    integer cases;
    integer s;
    integer d;
    integer n;
    integer oracle;
    dma_burst_planner #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .MAX_BURST_BEATS(MAX_BURST_BEATS)
    ) dut (
        .src_addr(src_addr),
        .dst_addr(dst_addr),
        .remaining_bytes(remaining_bytes),
        .plan_valid(plan_valid),
        .plan_beats(plan_beats),
        .plan_bytes(plan_bytes)
    );

    task automatic check(input bit valid_expected, input integer beats);
        #1;
        if (plan_valid !== valid_expected ||
            plan_beats !== (valid_expected ? 9'(beats) : 9'd0) ||
            plan_bytes !== (valid_expected ? 13'(beats*BB) : 13'd0))
            begin
            $fatal(1, "planner src=%h dst=%h rem=%h got %b/%d expected %b/%d", src_addr, dst_addr,
                   remaining_bytes, plan_valid, plan_beats, valid_expected, beats);
        end
    endtask

    initial begin
        cases = 0;
        if (ADDR_WIDTH == 32 && DATA_WIDTH == 128 && MAX_BURST_BEATS == 16) begin
            fd = $fopen("build/planner_vectors.txt", "r");
            if (fd == 0) begin
                $fatal(1, "missing planner vectors");
            end
            while (!$feof(
                fd
            )) begin
                rc = $fscanf(fd, "%h %h %h %h\n", src_addr, dst_addr, remaining_bytes, expected);
                if (rc != 4) begin
                    $fatal(1, "malformed vector");
                end
                check(1, expected);
                cases = cases + 1;
            end
            $fclose(fd);
        end
        // Independent byte-room oracle across page positions and legal geometries.
        for (s = 0; s < 4096; s = s + (BB < 16 ? 16 : BB) * 3) begin
            for (d = 0; d < 4096; d = d + (BB < 16 ? 16 : BB) * 7) begin
                src_addr = ADDR_WIDTH'(s);
                dst_addr = ADDR_WIDTH'(d);
                n = 1 + ((s + d) / BB) % 512;
                if (ADDR_WIDTH == 12) begin
                    if (n * BB > 4096 - s) begin
                        n = (4096 - s) / BB;
                    end
                    if (n * BB > 4096 - d) begin
                        n = (4096 - d) / BB;
                    end
                end
                remaining_bytes = (ADDR_WIDTH + 1)'(n * BB);
                oracle = n;
                if (oracle > MAX_BURST_BEATS) begin
                    oracle = MAX_BURST_BEATS;
                end
                if (oracle > (4096 - s) / BB) begin
                    oracle = (4096 - s) / BB;
                end
                if (oracle > (4096 - d) / BB) begin
                    oracle = (4096 - d) / BB;
                end
                check(1, oracle);
                cases = cases + 1;
            end
        end
        src_addr = 0;
        dst_addr = 0;
        remaining_bytes = (ADDR_WIDTH + 1)'(4096);
        oracle = MAX_BURST_BEATS;
        if (oracle > 4096 / BB) begin
            oracle = 4096 / BB;
        end
        check(1, oracle);
        src_addr = '1 - ADDR_WIDTH'(BB - 1);
        remaining_bytes = (ADDR_WIDTH + 1)'(BB);
        check(1, 1);
        remaining_bytes = (ADDR_WIDTH + 1)'(BB * 2);
        check(0, 0);
        remaining_bytes = 0;
        check(0, 0);
        if (BB > 1) begin
            src_addr = 1;
            remaining_bytes = (ADDR_WIDTH + 1)'(BB);
            check(0, 0);
            src_addr = 0;
            dst_addr = 1;
            check(0, 0);
            dst_addr = 0;
            remaining_bytes = (ADDR_WIDTH + 1)'(BB + 1);
            check(0, 0);
        end
        $display("PASS planner AW=%0d DW=%0d MAX=%0d vectors/checks=%0d", ADDR_WIDTH, DATA_WIDTH,
                 MAX_BURST_BEATS, cases);
        $finish;
    end

endmodule
`default_nettype wire
