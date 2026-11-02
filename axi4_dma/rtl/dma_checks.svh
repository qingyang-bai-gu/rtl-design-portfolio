`ifndef DMA_CHECKS_SVH
`define DMA_CHECKS_SVH
// Simulation-only configuration checks shared by blocks with AXI geometry parameters.
`define DMA_CHECK_GEOMETRY \
    if (ADDR_WIDTH < 12 || ADDR_WIDTH > 64) begin \
        $fatal(1, "PARAM: ADDR_WIDTH must be 12..64"); \
    end \
    if (DATA_WIDTH < 8 || DATA_WIDTH > 1024 || DATA_WIDTH % 8 != 0 || \
        ((DATA_WIDTH/8) & ((DATA_WIDTH/8)-1)) != 0) begin \
        $fatal(1, "PARAM: DATA_WIDTH must be power-of-two bytes, 8..1024 bits"); \
    end \
    if (MAX_BURST_BEATS < 1 || MAX_BURST_BEATS > 256) begin \
        $fatal(1, "PARAM: MAX_BURST_BEATS must be 1..256"); \
    end
`endif
