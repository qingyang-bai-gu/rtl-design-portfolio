# Verified baseline and completed RTL/TB extension

The final **2026-11-01** `make clean check` completed with exit status 0. The run
rebuilt vectors and simulation binaries, rechecked formatting/style, and ran the
independent lint matrix against the final reviewed sources. Report hashes were then
compared with every current source file; all matched. Reports describe this complete run.

* **32 HDL files** pass pinned Verible formatting and configured style checks.
* **79 legal configurations** pass Verilator 5.046 `--lint-only --timing -Wall`.
* **23 Python unit tests** pass: 12 planner checks and 11 performance-model checks.
* **6,927 deterministic planner vectors** pass.
* **57 behavioral simulation configurations** pass with Icarus/vvp 13.0.
* **80 invalid parameter configurations** produce the intended `PARAM:` rejection.
* **6 monitor violations** produce `RV:` and **1 arbiter withdrawal** produces `CONTRACT:`.
* **4 elaboration-only arbiter checks** pass separately from behavioral verification.
* **166 performance checkpoints across 10 configurations** match the Python model
  exactly, including errors and reset/reuse; every measured-predicted difference is zero.

Python version is 3.10.7. All Icarus compile logs, including intentional parameter
rejections, were checked and contain no `warning:`, `sorry:` or `error:` diagnostics.
Unwaived Verilator warnings are errors. Waivers in `config/verilator.vlt` cover named
open outputs, ordinary verification blocking assignments/declaration initialization,
and particular testbench reset nets that intentionally have synchronous and
asynchronous consumers. No width, latch, driver or protocol warning was suppressed.

## Coverage matrix

| Layer | Parameter/configuration coverage | Behavioral coverage |
| --- | --- | --- |
| Planner | AW/DW/MAX 32/128/16, 12/8/1, 64/1024/256, 64/8/256, 12/1024/3 | Independent vectors, both page limits, alignment, endpoints and conservation |
| Read/write engines | First four geometries above | Address/data/result stalls, source bubbles, exact beats, RLAST/WLAST, all response classes, wrong IDs, read-error drain, early held B, reset/reuse |
| Synchronous buffer | Width/depth 128/1, 128/3, 128/4, 128/5, 128/16, 1/1, 1024/5 | Full/empty, wrap, simultaneous push/pop, show-ahead, occupancy, flush/reset, seeded stress |
| Controller | 32/128/16, 12/8/1, 64/1024/256 | Descriptor validation, overlap/endpoints, planner-state interface, request/result sequencing, multi-burst errors and completions |
| AXI memory model | DW 8/128/1024 | Page-legal 1/3/16/256-beat fixtures, captured delays/injection, strobes, concurrent traffic, read-before-write, reset retention |
| Single-channel system | 32/128/16, 12/8/1, 64/1024/256, 32/128/3 | Whole-memory copy oracle, exact accepted AXI counts, page splits, later-chunk response/ID faults, cancellation/recovery |
| Arbiter | Requesters 1/3/4/5/8 | Independent cyclic-distance oracle, locked owner, changing competitors, saturated fairness, 4,000 seeded cycles/configuration, reset and withdrawal rejection |
| Multi-channel system | Channels/geometry 4:32/128/16, 3:32/128/3, 1:12/8/1, 5:64/1024/256; extra 3-entry queue and delay sweeps | Per-channel acceptance ledger, exact result order/routing/status/tag, duplicate cross-channel tags, saturated fairness, stalled result isolation, random traffic, invalid descriptors, page splits, errors, partial-read/write reset, whole-memory effects, all counters |
| Counters | Width 1/4/32/64 | Every event, simultaneous increments, modulo wrap, independent integer totals, reset |
| Reset and bit synchronizers | Stages 2/3/4 | Exact digital latency, asynchronous assertion, release with local edges only, stopped clock |
| Async FIFO | Width/depth/half-periods/phase 1/2/3:5/1, 128/4/2:7/3, 1024/8/7:2/0, 17/16/3:3/0 | Exact capacity, many wraps, full/empty stalls, record order/integrity, reset while full, stopped writer/reader, recovery and ready/valid stability |
| Two-clock system | Channels/depth/control:AXI half-periods/AXI phase 4/4/3:5/1, 3/2/7:2/3, 1/8/2:7/4 | Same external system oracle; unrelated clocks/phases, descriptor/result CDC, backpressure, either reset request and stopped-clock reset/reuse |
| Stability checker | Positive plus six intentionally invalid modes | Held payload, valid withdrawal, X/Z controls and unknown payload rejection |

All table clock values are simulation nanoseconds, not hardware operating claims.
Full extension memory comparisons cover 131,072 bytes (4,096 for minimum address width).
The widest-data burst fixtures remain within a 4-KiB page; actual 256-beat AXI encoding
is covered by narrow data, since a 1024-bit beat allows only 32 beats per page.

New deterministic seeds include arbiter `A8B17E19`, multi-channel producer `47C4A11E`,
consumer `C0A51DE5`, async FIFO `5B00318F/701ABB9E`, and counters `418F007D`. Baseline
seeds remain planner `A414D00D`, engines `1BADF00D`, buffer `B00FCAFE`, system `DA4A2026`.
Watchdogs and subprocess timeouts turn missing progress into test failures.

## Reproducible evidence and limits

Reviewed reports: [behavioral results](verification_results.json),
[lint results](lint_results.json), [style results](style_results.json), and
[performance comparisons](performance_results.json). They record versions, source
hashes and outcomes; detailed run logs remain in ignored `build/`.
[CODE_REVIEW.md](CODE_REVIEW.md) records design/verification review and corrections.

This evidence establishes tested digital behavior, static lint, formatting and model
agreement within the documented scope. It does not establish formal proof, synthesis,
RAM/macro mapping, physical CDC/RDC, metastability MTBF, timing, area or power signoff.
See [CDC.md](CDC.md) for reset assumptions and physical integration obligations, and
[PERFORMANCE.md](PERFORMANCE.md) for the service-cycle prediction boundary. Reset must
also cancel the attached slave's channel state. Accepted writes survive cancellation;
no timeout or arbitrary malformed-slave recovery is promised.

Markdown coverage rows, URLs and hash JSON are intentional exceptions to the strict
100-column HDL rule.
