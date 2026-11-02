# Measured service cycles and software prediction

`dma_performance_counters` observes AXI-domain events only. All counters reset to zero
and wrap modulo `2**COUNTER_WIDTH`. Read them in the AXI domain; coherent asynchronous
readout is outside this interface. Several counters may increment on one edge.

| Counter | Increment condition at an AXI rising edge |
| --- | --- |
| `cycle_count` | Each non-reset clock edge, including idle |
| `active_cycle_count` | Shared owner is active |
| `descriptor_count` | Descriptor accepted by shared core, after arbitration |
| `completion_count` | Core result accepted into owner's result queue |
| `error_count` | Same result handshake with nonzero status |
| `read_burst_count`, `read_beat_count` | AR handshake, R handshake |
| `write_burst_count`, `write_beat_count`, `write_response_count` | AW, W, B handshake respectively |
| `ar_stall_count`, `r_stall_count`, `aw_stall_count`, `w_stall_count`, `b_stall_count` | Corresponding VALID asserted with READY low |

The active interval excludes the dispatch edge and includes the result acceptance
edge. `completion_count` precedes external consumption and may precede CDC delivery.
Stall totals can overlap and do not sum to active cycles. A partial reset-cancelled
copy contributes accepted AXI events before counters are cleared.

## Prediction boundary

`model/performance.py` uses integer burst planning and explicit slave-delay inputs.
It predicts core service cycles from descriptor acceptance to core result acceptance.
It excludes arbitration, descriptor queue residence, control/AXI clock ratio, CDC
latency, and downstream result residence. Completion credit ensures that core result
acceptance is not stalled by another channel. This is an exact model of the current
serial architecture against the configurable verification memory fixture, not a
throughput claim for an arbitrary memory controller.

For a successful N-beat chunk the body is:

`3*N + 9 + dAR + N*dR + dAW + N*dW + dB`

Sum the bodies and add one final completion cycle. The three beat terms account for
read beats, FIFO-to-write staging and write beats; nine fixed cycles cover planning,
engine issue/turnaround and results. Delays follow the memory fixture's precise
handshake contract: once per address/response, once per beat on R/W. Each descriptor
uses its own source/destination page boundaries and maximum-burst setting.

An invalid descriptor takes one service cycle with no bus traffic. A read-error chunk
fully drains its expected N beats, suppresses its write and terminates with
`2*N+6+dAR+N*dR` cycles, including failure completion, after any successful prefix
bodies. A write-error chunk retains its accepted writes and terminates after its body
plus one completion cycle. Remaining chunks are omitted. The model validates fault
location, geometry and descriptor-error assumptions.

Hand-calculated zero-delay anchors, checked by Python tests, include:

| Copy at 128-bit data, max 16 beats | Predicted service cycles |
| --- | ---: |
| One beat | 13 |
| One full 16-beat chunk | 58 |
| 64 beats in four chunks | 229 |
| Six beats split 1/1/4 by different source/destination boundaries | 46 |

## Measurement and comparison

`tb_multi` has an interface-only acceptance ledger, AXI phase/byte scoreboard and
independent event totals. At drained checkpoints it checks every hardware counter,
including idle elapsed edges and stalls. It emits descriptor/delay records, reset
boundaries and measured active counts. `scripts/regress.py` separately feeds those
records to the Python model, compares every checkpoint, and fails on any mismatch.
Reset discards the cancelled ledger in both scoreboards and the software model.

`performance_results.json` records the measured and predicted values for all
single-clock and dual-clock configurations. It includes the model hash; the full
verification report records RTL, TB, model and script hashes. The regression sweeps
zero and nonzero delays, burst/page splits, channel counts, errors, and reset/reuse.
A zero model gap establishes agreement only within this stated boundary. Cycle
prediction against arbitrary AXI latency and performance optimization are future work.

## Reviewed measured examples (2026-11-01)

The clean regression compared 166 checkpoints across ten configurations. The first
saturated batch in selected cases gave:

| Configuration | Descriptors | Predicted | Measured | Gap |
| --- | ---: | ---: | ---: | ---: |
| Four channels, default delays | 12 | 396 | 396 | 0 |
| Four channels, zero added delays | 12 | 228 | 228 | 0 |
| Four channels, asymmetric delay sweep | 12 | 456 | 456 | 0 |
| One channel, one-byte data, maximum one beat | 3 | 183 | 183 | 0 |
| Four channels with control/AXI CDC | 12 | 396 | 396 | 0 |

Units are AXI core service cycles, with queuing and CDC wait excluded. Remaining
checkpoints, including injected failures and reset epochs, are retained in
[performance_results.json](performance_results.json). This run found no model gap
inside that boundary; it does not predict end-to-end asynchronous request latency.
