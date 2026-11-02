# RTL and testbench review

Review date: 2026-11-01. Scope: the single-channel core, channel arbitration,
queue ownership, performance counters, reset synchronization and asynchronous
record FIFOs, together with their verification models and testbenches.

## Design and protocol review

* `rtl/round_robin_arbiter.sv:25`: combinational scan defaults every output and wraps
  explicitly for non-power-of-two requester counts. At line 54 priority changes only
  after an accepted grant; stalled ownership is retained. The line 80 contract checker
  rejects a requester withdrawing a held offer. Fairness is by accepted descriptor.
* `rtl/axi_dma_multi.sv:139`: owner state is captured at core acceptance and retained
  until the tagged result is queued. Line 151 makes only nonempty channels with result
  space eligible. With one global active copy, that space is reserved until completion;
  a blocked channel cannot consume another channel's queue or prevent eligible peers.
* `rtl/axi_dma_cdc.sv:108`: either asynchronous reset request cancels both domains.
  The two local release pipelines prevent release without local clock edges. Complete
  descriptor/result records use per-channel FIFOs; AXI datapath and telemetry remain
  in the AXI domain. This is global cancellation, not isolated one-sided FIFO reset.
* `rtl/dma_async_fifo.sv:44`: source binary pointers and registered Gray encodings advance
  only on handshakes. The top-two-bit mask works at depth two. Line 66 resets pointers
  asynchronously, including with stopped clocks; only memory writes use the write
  clock and storage is not reset. Full/empty use next pointers and synchronized remote
  state conservatively. Memory inference and routed crossing constraints need a target.
* `rtl/dma_performance_counters.sv:42`: each event increments its own explicitly sized
  counter, with modulo wrap and reset. Active cycles represent core service; result
  counting occurs before external consumption. The software model states this boundary.

The baseline core's serial read/resolve/write/resolve behavior is retained. Read
errors drain the expected beat count, suppress the chunk's writes and flush its data;
write errors stop later chunks while preserving accepted writes. AXI IDs stay zero and
returned IDs are checked. Reset cancellation still requires a coordinated slave reset.
There is no timeout for an indefinitely stalled or malformed slave.

## Verification review and corrections

The arbiter oracle ranks cyclic distance independently from the RTL scan and tests
locked winners, changing competitors, saturated fairness, reset/reuse and prohibited
withdrawal. Counts include non-powers of two and a single requester.

`tb/tb_multi.sv` records accepted descriptors per channel, identifies expected bursts
from that ledger, validates all accepted AXI phases/bytes, and checks exact result
order/status/tag on the owning interface. The scoreboard never reads DUT internal
state. Deliberate duplicate tags across channels ensure routing cannot be inferred
from tag uniqueness. Whole-memory comparisons include untouched bytes. Saturated
traffic, result-queue stalls, page splits, invalid descriptors, later-chunk read/write
response and ID errors, random lengths/backpressure, partial-work resets and reuse
are exercised. The CDC cases also stop each clock during reset and recovery.

The initial one-byte configuration exposed a testbench assumption that a stalled
completion would appear within 30 cycles. The sequence now waits for the observable
completion, then checks that it remains held while peers have drained. A watchdog
still bounds the run. Fixture address bounds and arithmetic casts were strengthened
after lint review. A reserved SystemVerilog identifier was replaced in the FIFO bench.
These were verification/portability corrections, not changes to baseline DMA semantics.

FIFO unit scoreboards compare accepted records without using internal pointers.
They exercise exact capacity, empty/full backpressure, many wraps, equal and unrelated
clocks, resets while full, stopped reader/writer clocks and recovery. Synchronizer
units check exact digital stage latency, asynchronous assertion and stopped-clock
release. Counter units check every event, simultaneous increments, narrow-width wrap
and reset. Performance-model unit tests include hand-calculated anchors and parser
rejection of mismatches; integration compares measured counts after each drained batch.

All HDL uses the same pinned formatting, named connections, explicit control blocks,
width guards and strict lint. Verification drivers use falling edges; observers sample
rising-edge handshakes and compare registered results after updates. Mixed-reset lint
waivers are limited to named reset signals in three testbenches, where asynchronous
CDC state deliberately shares reset with synchronous core/checkers. No width, latch,
driver, or protocol warning is hidden. The old inactive-shell waiver was removed and
the elaboration-only bench renamed to describe its limited purpose.

## Outcome and limits

See VERIFICATION.md and the hash-bound JSON reports for the final clean-run counts.
No required correction remains within the documented functional scope after review
and verification. This is a bounded engineering assessment, not production signoff.
Formal proof, synthesis, target memory mapping, CDC/RDC structural analysis, MTBF,
physical constraints, timing, area and power are unverified. CDC.md records the
integration obligations; PERFORMANCE.md explains the measured-model scope.

Optional follow-on work is to select a hardware target and perform synthesis plus
physical CDC/timing closure before making hardware claims. Those milestones require their own constraints and verification reports.

## Change-review requirements

Review findings identify current files/lines, consequences and corrections. Required
fixes are distinguished from optional improvements. Each closeout checks design
responsibilities, handshakes, reset, parameters, verification and readability, then
records formatting changes, executed checks and remaining limits. Source, tests,
documentation and evidence are kept consistent in the same reviewed change.
