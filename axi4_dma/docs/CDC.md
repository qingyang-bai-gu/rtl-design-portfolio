# Clock/reset crossing inventory and integration contract

`axi_dma_cdc` keeps the controller, burst buffer, engines, arbiter, queues, counters
and every AXI signal in `axi_clk`. `ctrl_clk` handles descriptor submissions and
completion consumption. There is no AXI data-channel crossing.

## Crossing inventory

For each channel, `g_channel[channel].descriptors` crosses a complete
`{source, destination, length, tag}` record, width `3*ADDR_WIDTH+1+TAG_WIDTH`.
`g_channel[channel].completions` crosses `{tag, status}`, width `TAG_WIDTH+2`.

| Path | Source -> destination | Mechanism |
| --- | --- | --- |
| Descriptor storage | control -> AXI | Dual-clock show-ahead storage, qualified by synchronized pointers |
| Descriptor `wr_gray` | control -> AXI | Registered Gray value through two `cdc_bit_sync` stages |
| Descriptor `rd_gray` | AXI -> control | Registered Gray value through two stages |
| Completion storage | AXI -> control | Same FIFO mechanism, reverse direction |
| Completion `wr_gray` | AXI -> control | Registered Gray value through two stages |
| Completion `rd_gray` | control -> AXI | Registered Gray value through two stages |
| Both reset requests | asynchronous -> both | AND of active-low requests; one `reset_sync` per domain |
| Counter outputs | AXI -> external AXI-domain observer | No crossing provided; a control-domain reader needs a separate snapshot protocol |

`cdc_bit_sync` is suitable for independent levels and Gray pointers only. It does not
make an arbitrary multi-bit record coherent and does not guarantee capture of short
pulses. Full records cross through FIFOs, not parallel bit synchronizers.

## FIFO invariants

`dma_async_fifo` requires power-of-two depth >=2. Binary pointers include an extra
wrap bit. Each source registers its binary and Gray pointers on an accepted transfer.
Empty compares the next read Gray pointer to the synchronized write pointer. Full
compares the next write Gray pointer against the synchronized read pointer with its
top two bits inverted. This also works at depth two without a zero-width slice.

Flags are conservative: freeing space or making a record visible takes synchronization
and local flag-update latency. Push/pop enables are qualified by local reset and
full/empty. The single writer never modifies an unread entry; stale synchronized
pointers can postpone progress but cannot authorize overwrite or underflow under the
reset and physical crossing assumptions. Show-ahead payload remains stable under stall.
The storage array has one write clock, an asynchronous read and no memory reset.
Target-specific RAM inference or memory-macro replacement needs separate review.

## Global reset topology

`common_arst_n = ctrl_arst_n && axi_arst_n`. Either request asserts both domain reset
outputs immediately. `reset_sync` releases its output only after two local clock edges.
The common assertion clears FIFO pointers and synchronizer banks asynchronously,
including when a clock is stopped. FIFO storage is logically discarded, not erased.
Baseline core state and synchronous per-channel queues remain reset for the local
release interval before reuse.

This is global cancellation triggered from either side. Isolated FIFO-side reset is
unsupported. Reset requests must be glitch-free and meet target minimum pulse widths.
Both clocks must eventually run for both domains to leave reset. The AXI slave must
use `axi_domain_rst_n` (or an equivalent coordinated reset) to cancel abandoned bus
transactions. Accepted writes survive reset; descriptors/results do not. Queued work
may be accepted in a released domain while its peer is still held in reset and waits
until that peer resumes. An integrator must honor the ready/valid outputs throughout.

## Evidence and physical limits

The functional regression checks exact records and byte effects with unrelated clock
ratios/phases, sustained wraparound, full/empty boundaries, held payloads, backpressure,
and either reset request. Directed tests stop each clock during reset and verify no
stale completion or pointer survives when the clock restarts. Zero-delay digital
simulation cannot model metastability, prove MTBF, or establish routed Gray-bus skew.

Before hardware use, select a technology/clock plan, preserve and place the `ASYNC_REG`
stages, check reset recovery/removal, and run structural CDC/RDC plus timing analysis.
Resolve source Gray registers and first synchronizer stages for every FIFO instance
explicitly in the synthesized netlist. Bound Gray-bus skew below the minimum source
transition interval with margin; a conservative bound uses the faster clock period.
Apply the target flow's appropriate datapath maximum-delay constraints as well, review
exception precedence, and inspect constraint coverage and routed reports. The
storage-to-read-data path also needs the target memory/bundled-data timing analysis;
it is not made safe by a blanket false-path declaration. No target constraints or
physical signoff are supplied by this technology-independent RTL release.

These integration requirements are informed by primary vendor documentation:
[AMD bus-skew constraints](https://docs.amd.com/r/en-US/ug903-vivado-using-constraints/About-Bus-Skew-Constraints),
[AMD asynchronous clock crossings](https://docs.amd.com/r/en-US/ug903-vivado-using-constraints/Asynchronous-Clock-Domain-Crossings),
and [AMD synchronized reset release](https://docs.amd.com/r/en-US/ug1387-acap-hardware-ip-platform-dev-methodology/Synchronous-Reset-vs.-Asynchronous-Reset).
The project RTL and benches were written independently; no vendor or third-party
FIFO implementation was imported.
