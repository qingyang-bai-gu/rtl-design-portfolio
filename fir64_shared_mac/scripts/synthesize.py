#!/usr/bin/env python3
"""Yosys structural synthesis; optional standard-cell mapping with a user Liberty."""
import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
RTL = "rtl/reset_sync.sv rtl/async_fifo.sv rtl/sample_sram.sv rtl/coeff_rom.sv rtl/fir64_shared_mac.sv"


def quote(path):
    # Quoting for the Yosys command language; no shell is involved.
    return '"' + str(path).replace('\\', '\\\\').replace('"', '\\"') + '"'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--liberty", type=Path)
    args = parser.parse_args()
    if not shutil.which("yosys"):
        raise SystemExit("yosys is not installed. Install it, then rerun this target.")
    if args.liberty and not args.liberty.is_file():
        raise SystemExit(f"Liberty file not found: {args.liberty}")
    build = ROOT / "build"
    build.mkdir(exist_ok=True)
    commands = [f"read_verilog -sv -DSYNTHESIS {RTL}", "hierarchy -check -top fir64_shared_mac",
                "proc", "flatten", "opt", "memory_dff", "memory_collect", "opt", "check -assert",
                "tee -o build/synth_generic_stat.json stat -json", "write_json build/synth_generic.json"]
    if args.liberty:
        lib = quote(args.liberty.resolve())
        commands += ["synth -top fir64_shared_mac -flatten", f"dfflibmap -liberty {lib}",
                     f"abc -liberty {lib}", "clean", "check -assert",
                     f"tee -o build/synth_mapped_stat.json stat -json -liberty {lib}",
                     "write_verilog -noattr -noexpr build/fir64_mapped.v"]
    script = build / "synth.ys"
    script.write_text("\n".join(commands) + "\n")
    result = subprocess.run(["yosys", "-l", "build/synthesis.log", "-s", str(script)],
                            cwd=ROOT, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    if result.returncode:
        raise SystemExit(result.stdout)
    netlist = json.loads((build / "synth_generic.json").read_text())
    cells = netlist["modules"]["fir64_shared_mac"]["cells"]
    types = Counter(cell["type"] for cell in cells.values())
    if types["$mul"] != 1:
        raise SystemExit(f"Expected one shared multiplier, found {types['$mul']}")
    summary = {"cell_types": dict(sorted(types.items())), "shared_multipliers": types["$mul"],
               "note": "Generic memory cells are not characterized SRAM macros; no technology area is implied."}
    if args.liberty:
        summary["liberty"] = str(args.liberty.resolve())
        summary["liberty_sha256"] = hashlib.sha256(args.liberty.read_bytes()).hexdigest()
    (build / "synthesis_summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    print("PASS synthesis: one shared multiplier. See build/synthesis.log and synthesis_summary.json.")
    if args.liberty:
        print("Mapped standard-cell netlist written. SRAM/FIFO arrays are mapped to registers and muxes.")


if __name__ == "__main__":
    main()
