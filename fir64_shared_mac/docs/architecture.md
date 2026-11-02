# Datapath and sequencing

## Sample storage

The asynchronous FIFO stores only accepted input samples. The controller removes
a sample when idle and its output holding register is either empty or being
consumed. On that edge, it writes the sample to `write_ptr`, saves that address in
`base_ptr`, advances `write_ptr` modulo 64, and clears the accumulator.

For tap `k`, the history address is `(base_ptr - k) modulo 64`, paired with
coefficient address `k`. Both memories have one-cycle synchronous reads. The
history wrapper has a 16-bit write port and a 16-bit read port; this sequencer
never enables both on the same edge, allowing a target-specific single-port
implementation as well.

No reset loop touches SRAM. `history_count` grows to 64 after reset; products for
tap indices at or beyond that count are replaced with zero. This implements
zero-padded startup without depending on power-up RAM contents. A conditional
selection masks unknown data in simulation; multiplying unknown data by zero
would not accomplish that.

## Processing schedule

Let edge N be a FIFO removal/sample SRAM write:

| Edge | State before edge | Action |
| --- | --- | --- |
| N | IDLE | Accept current sample; write SRAM; clear accumulator and tap index |
| N+1 | PRIME | Request SRAM and ROM tap zero |
| N+2 | MAC, tap 0 | Accumulate product zero; request tap one |
| N+3…N+64 | MAC, taps 1…62 | Accumulate current responses; request next tap |
| N+65 | MAC, tap 63 | Accumulate final product; register rounded output and exact sum; assert valid |
| N+66 | IDLE | Earliest output handshake and next FIFO removal |

There are 64 multiplies per output, all performed by the same `sample_q * coeff_q`
expression. ROM and history responses are aligned by requesting their addresses
together. The final output uses `sum_next`, including product 63, rather than the
previous accumulator value. The accumulator is cleared once per accepted sample.

When an output stalls, the sequencer stays in IDLE and retains the output. FIFO
input backpressure eventually propagates to the producer. There is one output
holding register and no result FIFO or decimation. Total input-to-output latency
depends on FIFO occupancy, clock phase, and downstream readiness.

## Fixed-point arithmetic

Every input and coefficient is a two's-complement 16-bit integer representing a
Q1.15 value. Each product is signed 32-bit with 30 fractional bits. Sign extension
to 38 bits before addition provides six guard bits for the 64-term sum.
The all-−32768 case with all-−32768 coefficients gives +2^36 exactly, illustrating
why a signed 37-bit accumulator is insufficient.

For a raw accumulator `a`, the output integer before clipping is:

```
q = sign(a) * floor((abs(a) + 16384) / 32768)
```

It is then clipped to [−32768, 32767]. The magnitude/rounding intermediates are
39 bits so that negation and biasing are safe across the complete signed 38-bit
range. This rounding rule differs from simply adding a positive bias to a signed
value, which would round negative half-way values toward zero.

## Default coefficients

The illustrative lowpass uses cutoff 0.10 cycles/sample (0.20 of Nyquist), a
64-point Hamming window, and normalization to unit DC gain. Quantization rounds
to Q1.15, then a symmetric correction to the two center taps makes the integer
coefficient sum exactly 32768. The linear-phase group delay is 31.5 samples.
No application-specific passband or stopband requirement was provided.

Storage excluding controller/datapath registers: 1024 history bits, 1024
coefficient bits, and `16 * 2**FIFO_ADDR_BITS` FIFO bits (128 by default).
Coefficient ROM can instead become constants and logic during technology mapping.
