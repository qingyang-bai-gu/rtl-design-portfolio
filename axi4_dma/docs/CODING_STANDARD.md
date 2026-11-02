# RTL and verification coding standard

This is the project's consistent house style, informed by the public
[lowRISC SystemVerilog guide](https://github.com/lowRISC/style-guides/blob/master/VerilogCodingStyle.md)
and the [Verible style rules](https://chipsalliance.github.io/verible/lint.html).
The baseline and single-clock core retain synchronous active-low reset; CDC state
uses asynchronous assertion and synchronized local release. Four-space indentation
and uppercase parameter names remain the house style. Those deliberate choices
override differing defaults in external guides. Formatting and lint are review aids, not substitutes for design
and verification review.

Implement RTL and verification code against the documented interface and behavioral
contracts. Public AXI/SystemVerilog specifications and style guides are references;
external RTL and testbench implementations are not source material for this project.
Use clear responsibilities, meaningful names, explicit assumptions, and comments that
explain decisions. Every new or mechanically edited block must be understood
and reviewed. Prefer a small, direct implementation over unnecessary abstraction or
boilerplate, and be able to explain why each state, counter, handshake, and test exists.

## Formatting and naming

* Four spaces per indentation level and continuation; no tabs or trailing whitespace.
* Maximum 100 columns in HDL; final newline; one named signal declaration per line.
* One statement per line, except `for` headers. Use explicit `begin/end` control blocks.
* Lower snake case for modules, ports, signals, tasks, and functions; uppercase snake
  case for parameters, local constants, and enum state values. Enum types end in `_t`.
* Name files after their module. Use one module per file and `default_nettype none`,
  restoring `wire` at the end. Use local `timeunit 1ns / 1ps` declarations.
* Use explicit named parameter and port connections, including monitors. Explicitly
  open unused output ports with `.name()` rather than silently omitting them.
* Let the pinned formatter determine spacing, wrapping, and alignment. Separate
  declarations, combinational wiring, state updates, and verification helpers clearly.

## RTL design review

* Use four-state `logic`, `always_ff` with nonblocking register updates, and
  `always_comb` with blocking combinational assignments. Continuous `assign` is
  appropriate for simple wiring. A net initializer is not interchangeable with a
  variable initializer: dependent combinational signals require continuous assignments.
* One owner per stored signal. Default every combinational output; no unintended
  latches, implicit nets, multiple drivers, or combinational ready/valid loops.
* One-process registered FSMs are intentional here; a second next-state process is
  not required merely for style. Decode defensively with a default case.
* Retain synchronous active-low reset in the baseline and single-clock core. CDC
  reset pipelines, pointer synchronizers and async FIFO pointers explicitly use
  asynchronous assertion with locally synchronized release (see CDC.md). Suppress
  handshakes while reset is asserted; reset cancels work without completion. Never
  reset FIFO storage arrays.
* State/counters advance on accepted transfers. Hold valid and payload under stall.
  Check read results before writing; complete only after the final B is accepted.
* Validate unsigned parameters. Use safe derived widths, explicit casts/extensions
  where needed, full-range occupancy, and explicit non-power-of-two pointer wrap.
  Safe physical-width helpers allow invalid zero-width parameters to reach clear
  diagnostics without crashing elaboration; they do not make zero widths supported.
* Explain responsibilities, assumptions, edge cases, and nonobvious choices in concise
  comments. Do not claim timing, CDC, synthesis, formal, or performance evidence from
  simulation or lint alone.

## Testbench and model review

* Use ordinary procedural blocks for timed stimulus, scoreboards, and models.
  Drive on falling edges; observe accepted transfers at rising edges; inspect
  registered results after NBA updates. Do not introduce testbench/DUT edge races.
* Keep low-level drivers mechanical. Place scenario checks in the sequence or explicit
  self-checking case/expectation helpers. Document the latter's assertion contract.
* Use `automatic` tasks/functions with explicit argument and return types. Use a
  function for zero-time computation and a task for timing or transaction actions.
* Derive expected results from interfaces and independent oracles, not DUT state.
  Check exact accepted counts, full memory effects, stalled payloads, reset/error
  recovery, and parameter boundaries. Preserve deterministic seeds and watchdogs.
* Parenthesize complete boolean expressions before case comparisons. Monitors must
  detect both directions of handshake mismatches and reject unknown controls.
* Keep the AXI memory model verification-only. Preserve its read-before-write NBA
  semantics and transaction-scoped injection settings. Accepted writes survive reset.

## Commands and tools

From the project root:

```sh
make format  # mechanical formatting, then style checks
make style   # check without editing
make lint    # independent Verilator RTL and testbench lint matrix
make test    # full Icarus/Python behavioral and negative-test regression
make check   # style, lint, and full regression, in order
```

The formatter/linter is pinned to **Verible v0.0-3860-gf3da2ce6** for reproducibility
and Intel Mac compatibility. Download the matching archive from the
[official release](https://github.com/chipsalliance/verible/releases/tag/v0.0-3860-gf3da2ce6)
and put `verible-verilog-format` and `verible-verilog-lint` in `.tools/verible/bin/`.
Alternatively put them on PATH or set `VERIBLE_BIN` to their directory. The `.tools/`
cache is ignored by Git and retained by `make clean`. Formatter options and lint
rules are committed under `config/`; formatting parse errors must fail the command.

Install Verilator with your package manager. It must support `--lint-only`, `--timing`,
and the committed warning names. Exact reviewed versions and hashes are recorded in
verification evidence. All unwaived warnings are errors. Waivers are narrow and
explained in `config/verilator.vlt`: named open outputs, ordinary testbench blocking
assignments and declaration initializers, and specific reset nets in CDC testbenches
that deliberately feed both asynchronous CDC state and synchronous core/checkers.
Never add a waiver simply to obtain a green result; first inspect its cause.

## Required daily closeout feedback

At each day's end, review actual code and report:

1. Required corrections with current file/line numbers, concrete consequences, and
   an explanation of the appropriate correction. Distinguish optional improvements.
2. Design and protocol review: ownership, FSMs, handshake stability, reset, widths,
   buffering, errors, and meaningful synthesis implications within the documented scope.
3. Verification review: independent expectations, races, count accuracy, stalls,
   invalid inputs, deterministic stress, diagnostics, and demonstrated recovery.
4. Style consistency and any mechanical formatting cleanup applied automatically.
5. Commands/results, remaining limitations, and the technical conclusions from the review.

Explain functional defects with their consequences and verify the corrections.
Update verification evidence after required corrections and checks pass, review
the complete diff, and commit the intended source and documentation together.
