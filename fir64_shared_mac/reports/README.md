# Local verification snapshot

Recorded November 1, 2026, America/Los_Angeles, for this reconstruction.
These results do not represent the original 2023 project measurements.

| Evaluation | Result |
| --- | --- |
| Simulator | Icarus Verilog 13.0 stable |
| Integer reference checks | 4 tests passed |
| FIFO simulations | 12 configurations passed: depths 2/4/8/16, three clock ratios each |
| FIR simulations | 5 configurations passed, each with full corpus and post-reset replay |
| Exact FIR comparisons | 9,740 outputs and 9,740 full 38-bit accumulator sums matched |
| Reset recovery | Passed during accumulation, FIFO full, and held output |
| Output backpressure | Stable data and valid checked throughout stalls |
| Compute schedule | 65 processing edges from core sample removal to result registration verified |
| Port-only testbench mode | Passed against RTL; actual mapped simulation remains unexecuted |
| Activity parser | Case-sensitive identifiers, aliases, and X/Z handling checked |
| RTL activity | 10,325,049 known bit transitions across 69 unique VCD identifiers |
| Waveform duration | 1,520,672 ns, including resets, stalls, and post-reset replay |
| MATLAB | Installed R2022a license expired; generator and comparison not executed |
| Synthesis | Not measured: Yosys and a target library unavailable |
| Timing | Not measured: OpenSTA and a target library unavailable |
| Power | Not measured: no characterized library or gate-level/physical activity result |

The activity count includes clock and internal RTL signal transitions and counts
aliases once per VCD identifier. Different identifiers can represent logically
related signals. This count is not a capacitance-weighted switching metric and
does not imply an energy or power value.

Machine-readable snapshots:

- [regression.json](regression.json): per-configuration pass status and comparison count
- [activity.json](activity.json): VCD metadata and highest transition-count signals
- [tool_status.json](tool_status.json): executed and unavailable evaluation flows

The main lowpass test (depth 8, sample/proc half-periods 7/5 ns) reported 95,593
input stall cycles and 23,175 output stall cycles during its 1820-sample pass.
Each test then independently replayed 128 samples after resetting a stalled
output. The stress profile reached **+68,719,476,736 (+2^36)** and
**−68,717,379,584** in the exact accumulator; both output saturation directions
were exercised. The half profile exercised 443 positive and 280 negative exact
half-way cases in the full corpus. See [the vector manifest](../vectors/manifest.json).

`make test` refreshes `build/regression.json`; `make activity` also refreshes
`build/activity.json` and `build/activity.vcd`. The snapshots here are preserved
separately from build output. [PPA instructions](../docs/ppa.md) describe the
additional tools and technology inputs needed for new area, timing, and power
measurements.
