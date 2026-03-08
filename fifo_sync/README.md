# Synchronous FIFO

## Description
Parameterized synchronous FIFO supporting non-power-of-two depths.

## Features
- Parameterized depth and width
- Full capacity utilization
- Wrap-bit pointer scheme
- Simultaneous read/write support
- Self-checking testbench

## Files

rtl/fifo_sync.sv
    FIFO implementation

tb/tb_fifo_sync.sv
    Self-checking SystemVerilog testbench

sim/run_sim.sh
    Example simulation script
