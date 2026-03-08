#!/bin/bash

vcs -sverilog ../rtl/fifo_sync.sv ../tb/tb_fifo_sync.sv -o simv
./simv
#vcs -full64 -licqueue '-timescale=1ns/1ns' '+vcs+flush+all' '+warn=all' '-sverilog' design.sv testbench.sv  && ./simv +vcs+lic+wait  
