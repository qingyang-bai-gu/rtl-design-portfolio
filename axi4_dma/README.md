# AXI4 DMA

The design provides descriptor arbitration, independent channel queues,
measured performance counters, and an optional control/AXI clock boundary around the
reviewed single-channel core. The single-channel core is available as `axi_dma`.

## Build and verification

Use Python 3.10+, Icarus Verilog 13.0, Verilator and the pinned Verible tools described
in [CODING_STANDARD.md](docs/CODING_STANDARD.md) and [TOOLCHAIN.md](docs/TOOLCHAIN.md).

```sh
cd axi4_dma
make format       # apply the committed HDL format and check style
make clean check  # rebuild; check style, independent lint, Python and HDL regression
```

Logs, source hashes and machine-readable reports are written under `build/`.
`make test STAGE=arbiter`, `multi`, `counters`, `cdc_units`, or `cdc` selects extension
checks; the original planner/engine/buffer/controller/memory/system stages remain.
`parameters` and `extension_parameters` check intentional invalid configurations.

## Architecture and supported scope

| Top | Interface and behavior |
| --- | --- |
| `axi_dma` | One descriptor/result interface and one active copy |
| `axi_dma_multi` | Default four channels, per-channel descriptor/result queues, descriptor-granular round robin, one shared active copy |
| `axi_dma_cdc` | Same channels; complete records cross between control and AXI clocks through per-channel Gray-pointer FIFOs |

Each burst is read completely before it is written. Both source and destination
constrain bursts at 4-KiB boundaries. Defaults are 32-bit addresses, 128-bit data,
16-beat maximum, 8-bit tags, two queued descriptors and one queued result per channel.
AXI IDs are zero; returned IDs are checked. Status is `0=success`, `1=descriptor error`,
`2=read error`, `3=write error`. Tags need only be interpreted within their channel.

Supported copies are aligned, full-width, nonzero, nonoverlapping and contiguous,
using INCR bursts. Arbitration is fair among eligible channels by descriptor, without
a cycle bound on an indefinitely stalled AXI slave. A channel with a full result queue
cannot monopolize the shared core. See [EXTENSION_SPEC.md](docs/EXTENSION_SPEC.md).

The single-clock cores retain synchronous active-low reset and immediate handshake
suppression. The CDC top combines both asynchronous reset requests, asserts reset in
both domains immediately, and releases each with its local clock. Either request
cancels all queued and active work without completions. The attached AXI slave must
also reset its channel state; accepted writes remain in memory. See [CDC.md](docs/CDC.md).

The service-cycle model is checked against measured counters, including page splits,
slave delays and errors. It excludes descriptor queue and CDC wait; see
[PERFORMANCE.md](docs/PERFORMANCE.md). Verification reports and review limits are in
[VERIFICATION.md](docs/VERIFICATION.md) and [CODE_REVIEW.md](docs/CODE_REVIEW.md).

Unimplemented features include partial/unaligned beats, overlap/memmove, strides,
interrupts, AXI-Lite registers, weighted scheduling and multiple outstanding AXI
transactions. Simulation/lint evidence does not establish formal proof, synthesis,
physical CDC safety, timing, area or power signoff.
