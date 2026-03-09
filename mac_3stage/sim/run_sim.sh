#!/bin/bash

set -e

echo "Cleaning previous build..."
rm -rf simv simv.daidir csrc *.vcd

echo "Compiling design and testbench..."

vcs -full64 -licqueue \
-timescale=1ns/1ns \
+vcs+flush+all \
+warn=all \
-sverilog \
../rtl/mac_3stage.sv \
../tb/mac_3stage_tb.sv

echo "Running simulation..."

./simv +vcs+lic+wait

echo ""
echo "Simulation complete."
echo "Waveform file: mac_wave.vcd"
