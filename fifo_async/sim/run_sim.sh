#!/usr/bin/env bash
set -euo pipefail

project_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
sim_dir=$(mktemp -d)
trap 'rm -rf "$sim_dir"' EXIT

run_case() {
  iverilog -g2012 -Wall -s tb_fifo_async \
    -Ptb_fifo_async.DEPTH="$1" -Ptb_fifo_async.WIDTH="$2" \
    -Ptb_fifo_async.WR_HALF_PERIOD="$3" -Ptb_fifo_async.RD_HALF_PERIOD="$4" \
    -o "$sim_dir/tb_fifo_async.vvp" \
    "$project_dir/rtl/fifo_async.sv" "$project_dir/tb/tb_fifo_async.sv"
  vvp "$sim_dir/tb_fifo_async.vvp"
}

run_case 8 8 5 7
run_case 2 1 2 9
run_case 16 17 11 3
