#!/usr/bin/env python3
"""Golden-check a mapped netlist with Liberty-matching functional cell models."""
import argparse
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cells", type=Path, nargs="+", required=True,
                        help="Verilog standard-cell simulation models matching synthesis Liberty")
    args = parser.parse_args()
    for path in [ROOT / "build/fir64_mapped.v", *args.cells]:
        if not path.is_file():
            raise SystemExit(f"Missing file: {path}")
    count = json.loads((ROOT / "vectors/manifest.json").read_text())["samples"]
    compile_cmd = ["iverilog", "-g2012", "-DGATE_SIM", "-s", "tb_fir64", "-o", "build/gate.vvp",
                   "build/fir64_mapped.v", "tb/tb_fir64.sv", *[str(p.resolve()) for p in args.cells]]
    subprocess.run(compile_cmd, cwd=ROOT, check=True)
    result = subprocess.run(["vvp", "build/gate.vvp", f"+COUNT={count}", "+PROFILE=lowpass",
                             "+VCD=build/gate_activity.vcd"], cwd=ROOT, text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=300)
    (ROOT / "build/gate_simulation.log").write_text(result.stdout)
    print(result.stdout)
    if result.returncode or result.stdout.count("PASS FIR") != 2:
        raise SystemExit("Mapped netlist failed its golden checks; do not use this VCD for evaluation.")
    print("PASS gate simulation. VCD is zero-delay unless cell models provide delays; inspect annotation coverage.")


if __name__ == "__main__":
    main()
