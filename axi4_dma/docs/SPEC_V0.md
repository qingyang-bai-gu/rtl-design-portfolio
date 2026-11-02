# Single-channel DMA contract

This document defines transfer validation, engine interfaces, AXI attributes,
and reset behavior for `axi_dma`. Channel queueing and the two-clock wrapper
extend this contract as described in [EXTENSION_SPEC.md](EXTENSION_SPEC.md).

* Address width: 12–64. Data width: 8–1024, power-of-two whole bytes.
* Maximum burst: 1–256. FIFO depth: positive and at least maximum burst in the wrapper.
* Descriptor byte length is `ADDR_WIDTH+1` bits, allowing representable exclusive
  address-space endpoints. End calculations use another carry bit. An end exactly
  equal to `2**ADDR_WIDTH` is legal; an end above it is rejected.
* Descriptors use half-open intervals. Adjacent ranges are legal, intersecting ranges
  are rejected. Source, destination and length must be beat aligned; length nonzero.
* Engine requests have a 9-bit beat count (the actual count, including 256). Invalid
  counts produce one error result without AXI traffic. Engines assume other request
  fields are already planned, aligned and page-contained by their caller.
* IDs default to one bit in standalone engines. Wrapper requests use zero. Any
  nonzero AXI response code (including EXOKAY) is an error for these normal accesses.
* Read completion counts the requested beats, even for early/missing RLAST. A malformed
  slave must still supply the expected count. No timeout/repair of a nonresponsive or
  malicious slave is promised. Error flags accumulate only on accepted R beats.
* Write data uses a direct ready/valid stream. Its producer must hold data under stall.
  The integrated FIFO supplies this guarantee. Source pop equals W acceptance.
* Reset has priority over flush. Flush suppresses FIFO push-ready and pop-valid.
* No completion is issued for reset-canceled work. Memory effects already accepted
  through W remain observable. DMA and verification slave reset together.
* Fixed AXI attributes: INCR, full beat size, ID zero, normal nonexclusive transfers,
  cache/protection/QoS/region zero in the wrapper.

AXI burst encoding and page restrictions follow Arm's public
[AMBA AXI specification, IHI 0022H](https://developer.arm.com/-/media/Arm%20Developer%20Community/PDF/IHI0022H_amba_axi_protocol_spec.pdf).
