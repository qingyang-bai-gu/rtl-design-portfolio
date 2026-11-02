# Clock crossing and reset integration

## Logical design

The input FIFO uses separate binary read/write pointers to address the storage
array. Each has one extra wrap bit and is converted to registered Gray code
before crossing domains. A two-flop `ASYNC_REG` synchronizer samples each remote
Gray pointer. Full is registered in the write domain; empty is registered in the
read domain. Full comparison inverts the synchronized read pointer's two most
significant Gray bits. Empty compares the next read Gray pointer with the
synchronized write Gray pointer. Capacity is exactly the power-of-two depth.

Flags intentionally lag remote progress by synchronization latency. A newly
written entry cannot be read until its write pointer has crossed, and its data
remains stored until the reader consumes it and the read pointer crosses back.
FIFO storage uses clocked writes and an asynchronous read. It can map to flops
or appropriate dual-clock distributed memory, not directly to a synchronous-read
block RAM without adding read prefetch and changing the interface.

Both clocks share the same external `arst_n`. Reset assertion clears both pointer
domains asynchronously. Each domain releases through its own two-flop reset
synchronizer; ready and valid are suppressed until that local release.
Reset discards queued inputs, any partial sum, and a held result. SRAM contents
are not reset, but history validity is reset to zero. Reset of only one domain
while the other continues running is not supported.

## Physical implementation requirements

`constraints/fir64.sdc` is a **pre-layout functional STA example**. Its asynchronous
clock-group exception removes meaningless inter-clock setup/hold checks, but
also overrides ordinary crossing-path delay constraints. It does not demonstrate
Gray-bus skew closure.

For a real FPGA or ASIC integration:

1. Retain and closely place both stages of every pointer and reset synchronizer.
   Confirm the target tool recognizes `ASYNC_REG`; prevent retiming, duplication,
   and shift-register extraction across the two stages as appropriate.
2. Identify all Gray source register Q pins and corresponding first-stage
   synchronizer D pins in the final netlist. Check that every expected bit is
   matched; do not silently accept an empty wildcard collection.
3. Replace the broad asynchronous clock-group exception with endpoint-specific
   constraints. Bound each Gray crossing's datapath delay and inter-bit skew
   by a value below the faster clock period, with appropriate implementation
   margin. Use the target tool's max-delay/datapath and bus-skew commands; their
   syntax and exception precedence differ across tools. Do not false-path those
   same paths if that would disable the bound.
4. Keep synchronizer stage-one-to-stage-two timing active. Review other intentional
   crossings (FIFO storage data, common asynchronous reset) separately and apply
   reset recovery/removal and reset-tree methodology for the target technology.
5. Run CDC/RDC analysis and review all crossings and exceptions. Digital RTL
   simulation does not model metastability or demonstrate an MTBF target.

Memory inference and reset behavior must be checked again after replacing the
generic wrappers with vendor memories or ASIC SRAM macros.
