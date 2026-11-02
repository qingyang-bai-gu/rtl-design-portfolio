# Synthesis, timing, and power evaluation

## Status

The available local execution flow is Icarus + Python. Yosys, OpenSTA, a Liberty
library, SRAM macros, and physical parasitics were not available. Synthesis,
timing, and power scripts are **unexecuted integration flows**. No numeric area,
Fmax, slack, or watts are claimed. Functional test and RTL switching results
are recorded separately in `reports/`.

## Structural synthesis

With Yosys installed:

```sh
make synth
```

The script reads all five RTL files, elaborates and flattens the design, performs
process/logic optimization, merges synchronous memory read flops, collects memory
cells, and checks structural consistency. It writes:

- `build/synthesis.log` and the exact `build/synth.ys` script
- `build/synth_generic.json` and `build/synth_generic_stat.json`
- `build/synthesis_summary.json`

It fails if the optimized generic netlist does not contain exactly one `$mul`
cell. Generic cell counts and logical memory bits have no technology area unit.
Inspect inferred memory ports and registered-read behavior in the JSON/log.

## Standard-cell mapping

Supply a Liberty library with compatible flip-flops and combinational cells:

```sh
make synth-mapped LIBERTY=/absolute/path/cells.lib
```

The same script also runs generic gate synthesis, `dfflibmap`, and ABC mapping,
and writes `build/fir64_mapped.v` and `build/synth_mapped_stat.json`. It records
the Liberty hash for later consistency checks. This illustrative flow **maps
arrays into flops and muxes**. It does not insert SRAM macros. An ASIC SRAM
implementation requires a macro-specific wrapper, memory mapping, macro Liberty,
and physical views; a genuine macro result will differ materially.

Report area in the units of the chosen Liberty; do not label an unknown unit as
square micrometers. Record the library process, voltage, temperature, and tool
versions with every measurement. No library or proprietary model is bundled.

## Timing

With a `sta` executable from OpenSTA and the same Liberty:

```sh
make sta LIBERTY=/absolute/path/cells.lib
# Override assumed clock periods and optionally annotate physical parasitics:
python3 scripts/run_sta.py --liberty /absolute/path/cells.lib \
  --sample-period 14 --proc-period 10 --spef /absolute/path/design.spef
```

The example SDC expects a Liberty `time_unit` of 1 ns and sets sample/proc
periods to 14/10 ns, matching the default activity test. It uses 0.10 ns clock
uncertainty, 1.0 ns max and 0 ns min I/O delays, 0.10 ns data input transitions,
and a 0.01 output load in Liberty capacitance units. These are replaceable
integration assumptions. Default analysis uses ideal clocks and no wire
parasitics; it is not post-route timing or proof of 100 MHz operation.

Review `timing_constraints.rpt` for unconstrained endpoints, then
`timing_paths.rpt`, `timing_wns.rpt`, `timing_tns.rpt`, `sta_run.json`, and
`sta.log`. Inspect setup and hold separately. The intended arithmetic path may
include SRAM response → multiplier → accumulator adder → register; quantization
and saturation can also be limiting. Do not infer the critical path without
examining the mapped timing report. See [CDC requirements](cdc.md) before using
these exceptions in physical implementation.

## Power

Generate functional gate-level activity using the same golden testbench and
cell models that match the mapping library:

```sh
make gate-activity CELL_MODELS=/absolute/path/cells_sim.v
# Multiple model files are supported by the Python entry point:
python3 scripts/gate_activity.py --cells /path/cells.v /path/udp.v
make power LIBERTY=/absolute/path/cells.lib
```

The gate simulation disables RTL-internal FSM probes but retains output,
accumulator, backpressure, reset-recovery, and no-extra-output checks. It writes
`build/gate_activity.vcd` and `build/gate_simulation.log`. OpenSTA reads the
`tb_fir64/dut` scope, reports activity annotation coverage to
`build/power_annotation.rpt`, and writes internal, switching, and leakage power
to `build/power.rpt` using the library's power models. Supply `VCD=/path/file.vcd`
to the Make target for a different gate dump. For different clock periods, use
the Python STA entry point with matching period arguments.

Check annotation coverage and warnings before accepting any number. Optimized
names may not match; remaining activities may be inferred or defaulted. The
provided gate simulation is zero-delay unless its cell models supply delays;
it does not capture all physical glitches. There is no clock-tree or wire
capacitance without a suitable physical model/SPEF, and no SRAM-macro power
without a macro model. The whole regression waveform includes reset and stalls;
select a documented steady-state interval or a representative workload when
characterizing an application. Target-specific power tools may instead consume
SAIF or other activity formats after conversion.

`make activity` deliberately reports only RTL transition counts. A transition
count is neither an energy nor a power measurement.

## Primary tool references

- [Yosys synthesis flow](https://yosyshq.readthedocs.io/projects/yosys/en/latest/using_yosys/synthesis/synth.html)
- [Yosys command reference](https://yosyshq.readthedocs.io/projects/yosys/en/latest/cmd_ref.html)
- [OpenSTA commands and power/activity reporting](https://opensta.readthedocs.io/en/latest/Commands/)
- [OpenSTA timing and VCD power examples](https://github.com/The-OpenROAD-Project/OpenSTA/blob/master/doc/Examples.md)
