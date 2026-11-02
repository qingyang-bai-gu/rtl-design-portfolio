# Design decisions

## Responsibilities and sequencing

The burst planner is combinational and owns no state. The controller validates a
descriptor and registers each paired source/destination plan before issuing an engine
request. A full-burst FIFO separates read and write phases. Engine results use
independent ready/valid interfaces, with exactly one consumed result per request.
Read errors drain the expected beat count, flush buffered data and suppress AW for
that chunk. Write errors retain accepted W effects and stop subsequent chunks.

## Ownership and completion credit

The multi-channel wrapper stores descriptors and results independently per channel.
Only one descriptor owns the shared core at a time. Dispatch requires space in the
owner's completion queue, reserving that slot until the result arrives. This keeps
a stalled consumer from blocking eligible peers. Round-robin priority advances on
accepted grants and a stalled grant retains its selected owner.

## Reset and clock domains

The single-clock core uses synchronous active-low state reset and immediately gates
handshakes while reset is asserted. In the two-clock wrapper, either asynchronous
request resets both domains and each domain releases reset using its own clock.
FIFO pointers and synchronizer stages clear asynchronously so cancellation also
works when a clock is stopped. FIFO storage is not reset. Complete records cross
through asynchronous FIFOs; AXI channels and telemetry remain in the AXI domain.
The attached slave must participate in reset cancellation. See [CDC.md](CDC.md).

## Parameters and arithmetic

Typed unsigned parameters, safe minimum physical widths and explicit casts keep
arithmetic intent clear. Unsupported zero widths reach parameter diagnostics instead
of malformed arrays. Checks are simulation-only under `SYNTHESIS`; integrations
must choose legal values. Address endpoints use an extra carry bit, including a
65-bit exclusive endpoint for 64-bit addresses. Synchronous FIFO pointers wrap
explicitly for arbitrary positive depths; asynchronous FIFO depths are powers of two.

## Verification memory semantics

The verification-only memory model stores bytes and captures delay/error settings
per transaction. Nonblocking memory writes give read-before-write snapshots when
read-payload creation and W acceptance coincide. Reset cancels active channel state
while retaining accepted writes. Scoreboards compare independent byte images and
accepted interface events rather than internal DUT state.

## Evidence boundary

The repository records simulation, static lint and service-cycle model agreement.
Target-specific memory inference, synthesis, physical CDC/RDC, timing, area and power
require further evidence. See [VERIFICATION.md](VERIFICATION.md) and
[CODE_REVIEW.md](CODE_REVIEW.md).
