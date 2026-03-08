A parameterized synchronous FIFO implementation in Verilog.

The design supports:

 - configurable data width

 - configurable depth (including non-power-of-2 depths)

 - full capacity utilization (no wasted entry)

 - safe handling of simultaneous read and write

 - simple and synthesizable control logic

The FIFO uses pointer comparison with an additional wrap bit to distinguish full vs empty conditions.

Both read and write operations occur on the same clock domain, making this a synchronous FIFO.
