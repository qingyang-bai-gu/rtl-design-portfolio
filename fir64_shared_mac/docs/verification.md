# Verification recipe and scope

Run `make test`. The runner changes to the project root, verifies vector hashes,
checks arithmetic corner cases, compiles each case with Icarus `-g2012 -Wall`,
and exits nonzero on any mismatch, missing completion, tool failure, or timeout.
Logs and a machine-readable regression summary are written under `build/`.

## Reference corpus

`model/reference.py` has no third-party dependencies. Its FIR oracle is a direct
integer convolution rather than a reproduction of the RTL RAM controller.
All sums are arbitrary-precision Python integers; they are checked to fit the
RTL's signed 38-bit accumulator before output quantization.

The 1820-sample corpus includes startup zeroes, both impulse polarities and
tails, full-scale positive and negative steps and tails, alternating full-scale
samples, small odd values and other arithmetic boundaries, 1024 full-range random
samples, and a trailing zero flush. The PRNG is xorshift32 seeded with
`0x13579bdf`; its shifts are 13 left, 17 right, and 5 left. The low 16 bits of
each updated state are interpreted as signed two's complement.

Three static coefficient profiles reuse the corpus:

| Profile | Purpose |
| --- | --- |
| lowpass | Normal filter response, tap ordering, wrap, history startup and decay |
| stress | All taps −32768; exercise wide signed sums, +2^36, and both output clips |
| half | Tap zero 16384, other taps zero; exact positive/negative half-way cases |

Files use one hexadecimal word per line: 4 digits for signed 16-bit values and
10 digits for signed 38-bit values (top two padding bits zero). The manifest
contains SHA-256 hashes, coefficient sums, accumulator extrema, and arithmetic
coverage counts. `make vectors` regenerates; `make check-vectors` compares
without modifying files.

MATLAB implements the same PRNG, design formula, and quantization, with `conv`
as an independent direct-convolution oracle. Integer-valued double arithmetic is
exact for these inputs, because all sums and products are well below 2^53.
`make compare-matlab` compares all ten hex files after MATLAB generation.
MATLAB execution was unavailable locally because the installed license expired.

## Simulation matrix

| Test | Depth | Write/sample half-period | Read/processing half-period | Phase |
| --- | --- | --- | --- | --- |
| FIFO | 2, 4, 8, 16 | 3 ns | 5 ns | 2 ns |
| FIFO | 2, 4, 8, 16 | 7 ns | 5 ns | 2 ns |
| FIFO | 2, 4, 8, 16 | 5 ns | 13 ns | 2 ns |
| FIR lowpass | 8 | 7 ns | 5 ns | 2 ns |
| FIR lowpass | 2 | 337 ns | 5 ns | 3 ns |
| FIR lowpass | 16 | 5 ns | 7 ns | 1 ns |
| FIR stress | 8 | 7 ns | 5 ns | 2 ns |
| FIR half | 4 | 7 ns | 5 ns | 3 ns |

FIFO checks: exact capacity including minimum depth two; write inhibition while
full; read inhibition while empty; ordered data across many pointer wraps;
random traffic in both faster-writer and faster-reader cases; one-bit Gray
transitions; and reset while full followed by reuse.

FIR checks: ready/valid source behavior; 1820 rounded outputs and exact
accumulators per case; randomized source gaps; randomized sink readiness and
180-cycle forced sink stalls; output stability while stalled; 65-edge internal
compute latency; no concurrent history read/write; no extra outputs after drain;
reset during computation with pending input; and reset with a held output.
After the final reset each case checks the first 128 reference outputs again,
including zero-padded history over stale SRAM contents.

17 configurations compare `5 * (1820 + 128) = 9740` FIR outputs. This is directed
and randomized simulation coverage, not a formal proof, metastability analysis,
analog CDC model, or technology timing verification.

## Waveforms and switching

`make activity` reruns the regression and dumps one default-depth lowpass case
to `build/activity.vcd` (scope `tb_fir64/dut`). The activity parser counts
known-to-known bit transitions once per VCD ID, preserving alias names. It
excludes transitions involving X or Z and includes the complete test, including
reset and stalls. Toggle counts cannot be converted to watts without cell
capacitances, voltage, and a timing/power model.
