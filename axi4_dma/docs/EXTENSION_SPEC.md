# Multi-channel and CDC contract

This document specifies channel queueing, arbitration, completion ownership,
and control/AXI clock crossings. The transfer validation and error semantics
in [SPEC_V0.md](SPEC_V0.md) apply to the shared single-channel core.

## Channel ownership and queueing

`axi_dma_multi` defaults to four logical channels. `CHANNELS` may be any positive
integer. Packed interface vectors use the channel number as their outer index.
Each channel has a `DESCRIPTOR_DEPTH` synchronous input FIFO and a
`COMPLETION_DEPTH` synchronous output FIFO; both depths are positive and may be
non-powers of two. A ready/valid handshake transfers the complete record.

Descriptors contain source address, destination address, byte length and tag.
Completions contain tag and two-bit status. Tags may repeat across channels; the
channel is implicit in the queue. Per-channel descriptor and result order is preserved.
The producer holds valid/payload until acceptance or reset. The consumer may stall.
Acceptance into a queue does not imply that execution has started.

A channel is eligible when its descriptor queue is nonempty, its completion queue has
space, and the shared engine has no owner. Completion credit is reserved by admitting
only one global owner and permitting only that owner to push a result. No other
transaction can consume that reserved slot. A stalled completion on one channel
therefore prevents further dispatches from that channel without blocking eligible peers.

The arbiter starts at channel zero, scans cyclically, and advances to the accepted
winner's successor. A stalled grant retains its owner and payload even if new
requests arrive. Requesters must retain a stalled request. The simulation contract
checker rejects withdrawal. Under persistent eligibility each channel is served once
per round. Fairness is by complete descriptor, not bytes or bursts; descriptor lengths
can differ, so there is no equal-bandwidth or bounded-cycle guarantee.

The wrapper latches channel ownership at the core descriptor handshake and retains
it through the core result handshake. The existing `axi_dma` performs all bursts for
that descriptor. Its result is pushed only into the owner's result queue. Invalid
queued descriptors consume service and return a tagged error without AXI traffic.
Read/write faults terminate only that descriptor. No new AXI IDs are introduced.

## Reset and cancellation

The single-clock top retains the baseline synchronous state reset. Reset suppresses
interface handshakes immediately and cancels all FIFO entries, owner state, counters
and active engine work. Storage bytes are not reset. The integration must reset the
AXI slave's in-flight channel state as well. Already accepted writes are not rolled back.
There is no per-channel cancellation or transaction timeout mechanism.

The two-clock top follows the global cancellation contract in CDC.md. Independent
preservation of one domain's pending transactions during another domain's reset is
not supported. A stopped clock holds that domain in reset until local release edges.

## Parameters and telemetry

Baseline geometry remains 12..64 address bits, 8..1024 data bits in power-of-two whole
bytes, maximum 1..256 beats, positive tag/ID widths, and buffer depth at least the
maximum burst. Parameter checks are simulation diagnostics; synthesis/integration
must select legal parameters. Safe physical widths allow invalid zero values to reach
those diagnostics without malformed zero-width arrays.

Counters have positive `COUNTER_WIDTH` (default 64) and wrap modulo `2**COUNTER_WIDTH`.
They are AXI-domain outputs even on the CDC top. Meanings and prediction boundaries
are specified in PERFORMANCE.md; they are not an asynchronous software register bank.
`CDC_DEPTH` is at least two and a power of two. Both descriptor and completion crossing
FIFOs use that depth independently for each channel. AXI-domain queue depths remain
separate from crossing FIFO depth.

## Review scope

The single-clock subsystem consists of `axi_dma_multi`, the shared `axi_dma`
core, arbiter, queues and counters. `axi_dma_cdc` wraps that subsystem with per-channel
asynchronous record FIFOs and local reset-release pipelines. The regression checks
behavior, parameter boundaries and model agreement. Formal proof, synthesis,
physical CDC/RDC and timing signoff require separate target-specific work.
