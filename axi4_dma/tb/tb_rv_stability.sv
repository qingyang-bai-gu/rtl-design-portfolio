`default_nettype none
// Independent monitor contract checks, including deliberate four-state violations.
module tb_rv_stability;
    timeunit 1ns / 1ps;
    parameter int unsigned MODE = 0;
    logic clk = 1'b0;
    logic rst_n = 1'b0;
    logic valid = 1'b0;
    logic ready = 1'b0;
    logic [7:0] payload = 8'h19;

    always begin
        #5;
        clk = !clk;
    end

    rv_stability #(
        .WIDTH(8)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .valid(valid),
        .ready(ready),
        .payload(payload)
    );

    initial begin
        @(negedge clk);
        rst_n = 1'b1;
        valid = 1'b1;
        repeat (2) begin
            @(negedge clk);
        end
        case (MODE)
            0: begin
                ready = 1'b1;
                @(negedge clk);
                valid = 1'b0;
                payload = 8'h73;
                @(negedge clk);
                $display("PASS ready/valid stability monitor contract");
                $finish;
            end
            1: begin
                payload = 8'h73;
            end
            2: begin
                valid = 1'b0;
            end
            3: begin
                valid = 1'bx;
            end
            4: begin
                ready = 1'bx;
            end
            5: begin
                ready = 1'bz;
            end
            6: begin
                payload = 8'hxx;
            end
            default: begin
                $fatal(1, "invalid monitor test MODE");
            end
        endcase
        @(negedge clk);
        $fatal(1, "monitor did not reject intentional violation MODE=%0d", MODE);
    end

    initial begin
        #1000;
        $fatal(1, "monitor test watchdog");
    end
endmodule
`default_nettype wire
