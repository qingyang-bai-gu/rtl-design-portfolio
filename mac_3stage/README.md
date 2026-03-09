# 3-Stage Pipelined MAC (Multiply–Accumulate)

## Overview

This project implements a **parameterized 3-stage pipelined Multiply–Accumulate (MAC) unit** in SystemVerilog.

The design accepts two operands `a` and `b`, multiplies them, and accumulates the result into an output register. The pipeline allows the design to sustain **one result per clock cycle** after the pipeline is filled.

This type of structure is widely used in **DSP blocks, neural-network accelerators, and GPU arithmetic units**.

---

## Architecture

Pipeline stages:

| Stage   | Operation         |
| ------- | ----------------- |
| Stage 1 | Register inputs   |
| Stage 2 | Multiply `a * b`  |
| Stage 3 | Accumulate result |

The pipeline latency is **3 cycles**.

```
a,b → [Reg] → [Multiply] → [Accumulator] → dout
```

A `valid_in` / `valid_out` handshake is used to track valid data through the pipeline.

---

## Parameters

| Parameter | Description         |
| --------- | ------------------- |
| `W`       | Input operand width |
| `W_OUT`   | Accumulator width   |

Default configuration:

```
W = 16
W_OUT = 32
```

---

## Interface

| Signal    | Direction | Description        |
| --------- | --------- | ------------------ |
| clk       | input     | Clock              |
| areset    | input     | Asynchronous reset |
| valid_in  | input     | Input data valid   |
| a         | input     | Operand A          |
| b         | input     | Operand B          |
| dout      | output    | Accumulated result |
| valid_out | output    | Output data valid  |

---

## Testbench

The testbench performs randomized verification:

* Random operands
* Random valid signals
* Cycle-accurate reference model
* Automatic pass/fail checking
* Waveform dumping (`VCD`)

Waveforms can be inspected with **GTKWave** or **EDA Playground EPWave**.

---

## File Structure

```
mac_3stage/
│
├── rtl/
│   └── mac_3stage.sv
│
├── tb/
│   └── mac_3stage_tb.sv
│
├── sim/
│   └── run_vcs.sh
│
└── README.md
```

---

## Running Simulation (VCS)

From the `sim` directory:

```
./run_sim.sh
```

The script will:

1. Compile the RTL and testbench
2. Run the simulation
3. Generate a VCD waveform file

---

