# RTL Design Portfolio

SystemVerilog projects covering datapaths, control logic, buffering, bus interfaces,
and simulation-based verification.

| Project | Design focus | Documentation |
| --- | --- | --- |
| [AXI4 DMA](axi4_dma/) | Burst planning, channel arbitration, error handling, performance counters, and control/AXI clock crossings | [Architecture](axi4_dma/docs/ARCHITECTURE.md), [verification](axi4_dma/docs/VERIFICATION.md) |
| [Synchronous FIFO](fifo_sync/) | Parameterized storage, full/empty detection, and simultaneous reads/writes | [Project notes](fifo_sync/README.md) |
| [Three-stage MAC](mac_3stage/) | Registered inputs, multiplication, and accumulation | [Project notes](mac_3stage/README.md) |

## AXI4 DMA

The DMA supports aligned, full-width, contiguous copies with paired source/destination
4-KiB burst limits. A single-channel core is shared by a default four-channel wrapper
with descriptor-granular round-robin arbitration and independent completion queues.
An optional two-clock wrapper transfers descriptors and tagged results through
Gray-pointer asynchronous FIFOs while retaining the AXI datapath in one domain.

The checked-in verification evidence covers:

- 32 HDL files checked for consistent formatting/style and 79 static lint configurations.
- 57 behavioral configurations, 80 invalid-parameter checks, and protocol-checker tests.
- 23 Python unit tests and 6,927 deterministic planner vectors.
- 166 measured service-cycle checkpoints matching the software model.

Run the complete DMA checks with the tools described in its documentation:

```sh
cd axi4_dma
make clean check
```

The current DMA evidence covers simulation, static lint, and service-cycle model
agreement. Synthesis, target memory mapping, physical CDC, timing, area, and power
signoff remain future milestones. See the [DMA README](axi4_dma/README.md) for supported
transfers, reset assumptions, tool setup, and known limits.
