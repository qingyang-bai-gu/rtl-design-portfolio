# Asynchronous FIFO

`fifo_async` adapts the synchronous FIFO's `wr`, `rd`, `din`, and registered
`dout` interface to independent write and read clocks. `WIDTH` defaults to 8
and can be any positive integer. `DEPTH` defaults to 8 and must be a power of
two of at least 2. Every slot is usable.

- Drive `wr` and `din` in the `wr_clk` domain. A rising edge with `wr && !full`
  accepts one word after the write domain leaves reset.
- Drive `rd` in the `rd_clk` domain. A rising edge with `rd && !empty` updates
  `dout` after the read domain leaves reset. `dout` holds between accepted reads
  and should only be used once a read has completed after reset.
- Assert the shared active-high `rst` to flush the FIFO. Both domains reset
  asynchronously, and each releases reset through its own two-stage
  synchronizer. Allow at least two rising edges of the relevant clock after
  deasserting `rst` before counting transfers on subsequent edges.

Binary pointers address the dual-clock memory. Each domain passes its registered
Gray-coded pointer through a two-stage synchronizer to the other domain. `full`
belongs to `wr_clk`, and `empty` belongs to `rd_clk`. Space freed by a read or
data added by a write becomes visible to the opposite domain after pointer
synchronization and a local flag update.

For hardware integration, constrain the Gray pointer paths from the source
registers to the first synchronizer stage in each direction. The required timing
constraints depend on the target and clocks. [AMD CDC timing guidance](https://docs.amd.com/r/2022.2-English/ug949-vivado-design-methodology/Constraints-on-Individual-CDC-Paths)

## Simulation

From the repository root, run with Icarus Verilog and `vvp` on your `PATH`.

```sh
bash fifo_async/sim/run_sim.sh
```

The self-checking testbench covers capacity, empty reads, full writes, FIFO
ordering, pointer wraparound, reset with a stopped read clock, and concurrent
random traffic across three width, depth, and clock configurations.
