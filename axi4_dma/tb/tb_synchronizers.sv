`default_nettype none
module tb_synchronizers;
    timeunit 1ns / 1ps;
    parameter int unsigned STAGES = 2;
    logic clk = 0;
    logic clock_enable = 1;
    logic arst_n = 0;
    logic rst_n;
    logic [2:0] async_data = 0;
    logic [2:0] sync_data;
    logic [2:0] expected[STAGES];
    int release_edges = 0;
    always begin
        #5;
        if (clock_enable) begin
            clk = !clk;
        end else begin
            clk = 0;
        end
    end
    reset_sync #(
        .STAGES(STAGES)
    ) reset_dut (
        .clk(clk),
        .arst_n(arst_n),
        .rst_n(rst_n)
    );
    cdc_bit_sync #(
        .WIDTH(3),
        .STAGES(STAGES)
    ) data_dut (
        .clk(clk),
        .rst_n(rst_n),
        .async_data(async_data),
        .sync_data(sync_data)
    );
    always @(posedge clk or negedge arst_n) begin
        if (!arst_n) begin
            release_edges = 0;
        end else begin
            release_edges = release_edges + 1;
        end
        #0.1;
        if (rst_n !== (arst_n && release_edges >= STAGES)) begin
            $fatal(1, "reset release stage count");
        end
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < STAGES; i = i + 1) begin
                expected[i] = 0;
            end
        end else begin
            for (int i = STAGES - 1; i > 0; i = i - 1) begin
                expected[i] = expected[i-1];
            end
            expected[0] = async_data;
        end
        #0.2;
        if (sync_data !== expected[STAGES-1]) begin
            $fatal(1, "bit synchronizer stage count");
        end
    end
    initial begin
        #12;
        arst_n = 1;
        wait (rst_n);
        for (int i = 0; i < 100; i = i + 1) begin
            #17;
            // One Gray transition at a time; not a coherent arbitrary binary bus.
            async_data = 3'((i + 1) ^ ((i + 1) >> 1));
        end
        @(negedge clk);
        #1;
        clock_enable = 0;
        #3;
        arst_n = 0;
        #0.5;
        if (rst_n || sync_data != 0) begin
            $fatal(1, "asynchronous reset with stopped clock");
        end
        #11;
        arst_n = 1;
        #50;
        if (rst_n) begin
            $fatal(1, "reset released without local clock");
        end
        clock_enable = 1;
        wait (rst_n);
        repeat (STAGES + 2) begin
            @(negedge clk);
        end
        $display("PASS synchronizers stages=%0d release/assertion/stopped clock", STAGES);
        $finish;
    end
    initial begin
        #10000;
        $fatal(1, "synchronizer watchdog");
    end
endmodule
`default_nettype wire
