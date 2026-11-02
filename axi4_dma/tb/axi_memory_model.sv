`default_nettype none
// Verification-only, independent read/write slots. Byte storage survives reset.
module axi_memory_model #(
    parameter int unsigned ADDR_WIDTH = 32,
    parameter int unsigned DATA_WIDTH = 128,
    parameter int unsigned ID_WIDTH = 1,
    parameter int unsigned MEM_BYTES = 65536,
    localparam int unsigned DATA_BITS = DATA_WIDTH == 0 ? 1 : DATA_WIDTH,
    localparam int unsigned ID_BITS = ID_WIDTH == 0 ? 1 : ID_WIDTH,
    localparam int unsigned STROBE_BITS = DATA_WIDTH < 8 ? 1 : DATA_WIDTH / 8
) (
    input logic clk,
    input logic rst_n,
    input logic [15:0] cfg_ar_delay,
    input logic [15:0] cfg_r_delay,
    input logic [15:0] cfg_aw_delay,
    input logic [15:0] cfg_w_delay,
    input logic [15:0] cfg_b_delay,
    input logic [1:0] cfg_r_resp,
    input logic [1:0] cfg_b_resp,
    input logic cfg_r_bad_id,
    input logic cfg_b_bad_id,
    input logic [ID_BITS-1:0] arid,
    input logic [ADDR_WIDTH-1:0] araddr,
    input logic [7:0] arlen,
    input logic [2:0] arsize,
    input logic [1:0] arburst,
    input logic arvalid,
    output logic arready,
    output logic [ID_BITS-1:0] rid,
    output logic [DATA_BITS-1:0] rdata,
    output logic [1:0] rresp,
    output logic rlast,
    output logic rvalid,
    input logic rready,
    input logic [ID_BITS-1:0] awid,
    input logic [ADDR_WIDTH-1:0] awaddr,
    input logic [7:0] awlen,
    input logic [2:0] awsize,
    input logic [1:0] awburst,
    input logic awvalid,
    output logic awready,
    input logic [DATA_BITS-1:0] wdata,
    input logic [STROBE_BITS-1:0] wstrb,
    input logic wlast,
    input logic wvalid,
    output logic wready,
    output logic [ID_BITS-1:0] bid,
    output logic [1:0] bresp,
    output logic bvalid,
    input logic bready
);
    timeunit 1ns / 1ps;

    localparam int unsigned BB = DATA_WIDTH / 8;
    localparam logic [2:0] AXI_SIZE = 3'($clog2(BB));
    logic [7:0] mem[(MEM_BYTES > 0 ? MEM_BYTES : 1)];
    logic reading;
    logic writing;
    logic pending_b;
    logic rv;
    logic bv;
    logic [ADDR_WIDTH-1:0] rpos;
    logic [ADDR_WIDTH-1:0] wpos;
    logic [8:0] rleft;
    logic [8:0] wleft;
    logic [ID_BITS-1:0] read_id;
    logic [ID_BITS-1:0] write_id;
    logic [1:0] read_resp;
    logic [1:0] write_resp;
    integer ar_timer;
    integer aw_timer;
    integer r_timer;
    integer w_timer;
    integer b_timer;
    integer read_gap;
    integer write_gap;
    integer response_gap;
    integer lane;
    // Use a carry bit beyond the largest supported address; retain exclusive-end semantics.
    function automatic logic legal_burst(input logic [ADDR_WIDTH-1:0] byte_addr,
                                         input logic [7:0] encoded_length,
                                         input logic [2:0] beat_size, input logic [1:0] burst_type);
        int unsigned byte_count;
        logic [64:0] end_exclusive;
        byte_count = (int'(encoded_length) + 1) * BB;
        end_exclusive = 65'(byte_addr) + 65'(byte_count);
        legal_burst = burst_type == 2'b01 && beat_size == AXI_SIZE &&
            byte_addr % ADDR_WIDTH'(BB) == 0 &&
            int'(12'(byte_addr)) + byte_count <= 4096 && end_exclusive <= 65'(MEM_BYTES);
    endfunction

    assign arready = rst_n && !reading && !rv && ar_timer >= cfg_ar_delay;
    assign awready = rst_n && !writing && !pending_b && !bv && aw_timer >= cfg_aw_delay;
    assign rvalid = rst_n && rv;
    assign wready = rst_n && writing && w_timer == 0;
    assign bvalid = rst_n && bv;

    always @(posedge clk) begin
        if (!rst_n) begin
            reading <= 0;
            writing <= 0;
            pending_b <= 0;
            rv <= 0;
            bv <= 0;
            rpos <= 0;
            wpos <= 0;
            rleft <= 0;
            wleft <= 0;
            rid <= 0;
            rdata <= 0;
            rresp <= 0;
            rlast <= 0;
            bid <= 0;
            bresp <= 0;
            read_id <= 0;
            write_id <= 0;
            read_resp <= 0;
            write_resp <= 0;
            ar_timer <= 0;
            aw_timer <= 0;
            r_timer <= 0;
            w_timer <= 0;
            b_timer <= 0;
            read_gap <= 0;
            write_gap <= 0;
            response_gap <= 0;
        end else begin
            if (!arvalid || reading || rv) begin
                ar_timer <= 0;
            end else if (!arready) begin
                ar_timer <= ar_timer + 1;
            end
            if (!awvalid || writing || pending_b || bv) begin
                aw_timer <= 0;
            end else if (!awready) begin
                aw_timer <= aw_timer + 1;
            end
            if (arvalid && arready) begin
                if (!legal_burst(araddr, arlen, arsize, arburst)) begin
                    $fatal(1, "memory illegal AR addr=%h len=%d", araddr, arlen);
                end
                reading <= 1;
                rpos <= araddr;
                rleft <= {1'b0, arlen} + 9'd1;
                read_id <= arid ^ ID_BITS'(cfg_r_bad_id);
                read_resp <= cfg_r_resp;
                read_gap <= int'(cfg_r_delay);
                r_timer <= int'(cfg_r_delay);
                ar_timer <= 0;
            end
            if (reading) begin
                if (rv && rready) begin
                    rv <= 0;
                    if (rleft == 1) begin
                        reading <= 0;
                    end else begin
                        rleft <= rleft - 9'd1;
                        rpos <= rpos + ADDR_WIDTH'(BB);
                        r_timer <= read_gap;
                    end
                end else if (!rv) begin
                    if (r_timer > 0) begin
                        r_timer <= r_timer - 1;
                    end else begin
                        for (lane = 0; lane < BB; lane = lane + 1) begin
                            rdata[lane*8+:8] <= mem[int'(rpos)+lane];
                        end
                        rid <= read_id;
                        rresp <= read_resp;
                        rlast <= rleft == 1;
                        rv <= 1;
                    end
                end
            end
            if (awvalid && awready) begin
                if (!legal_burst(awaddr, awlen, awsize, awburst)) begin
                    $fatal(1, "memory illegal AW addr=%h len=%d", awaddr, awlen);
                end
                writing <= 1;
                wpos <= awaddr;
                wleft <= {1'b0, awlen} + 9'd1;
                write_id <= awid ^ ID_BITS'(cfg_b_bad_id);
                write_resp <= cfg_b_resp;
                write_gap <= int'(cfg_w_delay);
                w_timer <= int'(cfg_w_delay);
                response_gap <= int'(cfg_b_delay);
                aw_timer <= 0;
            end
            if (writing) begin
                if (wvalid && wready) begin
                    if (wlast !== (wleft == 1)) begin
                        $fatal(1, "memory WLAST placement");
                    end
                    for (lane = 0; lane < BB; lane = lane + 1) begin
                        if (wstrb[lane]) begin
                            mem[int'(wpos)+lane] <= wdata[lane*8+:8];
                        end
                    end
                    if (wleft == 1) begin
                        writing <= 0;
                        pending_b <= 1;
                        b_timer <= response_gap;
                    end else begin
                        wleft <= wleft - 9'd1;
                        wpos <= wpos + ADDR_WIDTH'(BB);
                        w_timer <= write_gap;
                    end
                end else if (w_timer > 0) begin
                    w_timer <= w_timer - 1;
                end
            end
            if (pending_b && !bv) begin
                if (b_timer > 0) begin
                    b_timer <= b_timer - 1;
                end else begin
                    bid <= write_id;
                    bresp <= write_resp;
                    bv <= 1;
                    pending_b <= 0;
                end
            end
            if (bv && bready) begin
                bv <= 0;
            end
        end
    end

    initial begin
        if (ADDR_WIDTH < 12 || ADDR_WIDTH > 64) begin
            $fatal(1, "PARAM: memory ADDR_WIDTH must be 12..64");
        end
        if (DATA_WIDTH < 8 || DATA_WIDTH > 1024 || DATA_WIDTH % 8 != 0 ||
            ((DATA_WIDTH / 8) & ((DATA_WIDTH / 8) - 1)) != 0) begin
            $fatal(1, "PARAM: memory DATA_WIDTH must be power-of-two bytes, 8..1024 bits");
        end
        if (MEM_BYTES == 0 || ID_WIDTH == 0) begin
            $fatal(1, "PARAM: memory geometry");
        end
    end

endmodule
`default_nettype wire
