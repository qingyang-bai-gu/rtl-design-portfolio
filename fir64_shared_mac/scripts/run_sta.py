#!/usr/bin/env python3
"""Run OpenSTA on a Liberty-mapped netlist, optionally using gate-level activity."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--liberty", type=Path, required=True)
    parser.add_argument("--vcd", type=Path)
    parser.add_argument("--spef", type=Path)
    parser.add_argument("--sample-period", type=float, default=14.0)
    parser.add_argument("--proc-period", type=float, default=10.0)
    args = parser.parse_args()
    if not shutil.which("sta"):
        raise SystemExit("OpenSTA (sta executable) is not installed.")
    if not args.liberty.is_file():
        raise SystemExit("Provide an existing .lib file with --liberty /path/to/cells.lib")
    library = args.liberty.read_text()
    if not re.search(r'time_unit\s*:\s*"1\s*ns"', library):
        raise SystemExit("This example SDC requires a Liberty time_unit of 1ns; adapt constraints for other units.")
    if min(args.sample_period, args.proc_period) <= 2.0:
        raise SystemExit("Example I/O delays assume clock periods > 2 ns; adapt constraints for faster clocks.")
    build = ROOT / "build"
    summary_path = build / "synthesis_summary.json"
    if not summary_path.is_file() or not (build / "fir64_mapped.v").is_file():
        raise SystemExit("Run make synth-mapped LIBERTY=/path/to/cells.lib first.")
    summary = json.loads(summary_path.read_text())
    if summary.get("liberty_sha256") != hashlib.sha256(args.liberty.read_bytes()).hexdigest():
        raise SystemExit("Liberty differs from the synthesis library; rerun synth-mapped.")
    env = dict(os.environ, FIR_LIBERTY=str(args.liberty.resolve()),
               FIR_SAMPLE_PERIOD_NS=str(args.sample_period), FIR_PROC_PERIOD_NS=str(args.proc_period))
    # Do not inherit stale task-specific optional settings from the caller.
    for name in ("FIR_VCD", "FIR_SPEF"):
        env.pop(name, None)
    for name, path in (("FIR_VCD", args.vcd), ("FIR_SPEF", args.spef)):
        if path:
            if not path.is_file():
                raise SystemExit(f"File does not exist: {path}")
            env[name] = str(path.resolve())
    result = subprocess.run(["sta", "-exit", "scripts/sta.tcl"], cwd=ROOT, env=env,
                            text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    (build / "sta.log").write_text(result.stdout)
    if result.returncode or re.search(r"(^|\n)(Error[: ]|FIR_STA_ERROR:)", result.stdout):
        raise SystemExit(result.stdout)
    run = {"kind": "pre-layout, ideal clocks; no extracted parasitics" if not args.spef else "SPEF annotated",
           "sample_period_ns": args.sample_period, "proc_period_ns": args.proc_period,
           "liberty": str(args.liberty.resolve()), "vcd": str(args.vcd) if args.vcd else None,
           "limitations": "Inspect unconstrained paths and activity coverage. Arrays use standard cells, not SRAM macros."}
    (build / "sta_run.json").write_text(json.dumps(run, indent=2) + "\n")
    print("OpenSTA reports written to build/. Review timing_constraints.rpt before interpreting slack.")
    if args.vcd:
        print("Review power_annotation.rpt: partial annotation and zero-delay simulation limit power accuracy.")


if __name__ == "__main__":
    main()
