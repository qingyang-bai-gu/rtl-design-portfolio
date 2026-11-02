#!/usr/bin/env python3
"""Run portable Icarus simulations and retain logs and measured coverage."""
import argparse
import json
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
RTL = ["rtl/reset_sync.sv", "rtl/async_fifo.sv", "rtl/sample_sram.sv",
       "rtl/coeff_rom.sv", "rtl/fir64_shared_mac.sv"]


def run(command, log=None):
    result = subprocess.run(command, cwd=ROOT, text=True, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, timeout=120)
    if log:
        log.write_text(result.stdout)
    if result.returncode:
        print(result.stdout)
        raise SystemExit(f"Command failed ({result.returncode}): {' '.join(map(str, command))}")
    if result.stdout.strip():
        print(result.stdout.strip(), flush=True)
    return result.stdout


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--vcd", action="store_true", help="dump one full FIR test to build/activity.vcd")
    args = parser.parse_args()
    for tool in ("iverilog", "vvp"):
        if not shutil.which(tool):
            raise SystemExit(f"Required tool not installed: {tool}")
    build = ROOT / "build"
    build.mkdir(exist_ok=True)
    run([sys.executable, "model/reference.py", "--check"])
    run([sys.executable, "-m", "unittest", "discover", "-s", "model", "-v"], build / "model.log")
    count = json.loads((ROOT / "vectors/manifest.json").read_text())["samples"]
    results = []
    for addr in (1, 2, 3, 4):
        exe = f"build/fifo_{addr}.vvp"
        run(["iverilog", "-g2012", "-Wall", "-s", "tb_async_fifo", "-o", exe,
             f"-Ptb_async_fifo.ADDR_BITS={addr}", *RTL[:2], "tb/tb_async_fifo.sv"])
        for wr, rd in ((3, 5), (7, 5), (5, 13)):
            name = f"fifo_depth{1 << addr}_{wr}_{rd}"
            output = run(["vvp", exe, f"+WR_HALF={wr}", f"+RD_HALF={rd}"], build / f"{name}.log")
            if output.count("PASS FIFO") != 2:
                raise SystemExit(f"Missing completion: {name}")
            results.append({"test": name, "status": "PASS"})
    configurations = [("lowpass", 3, 7, 5, 2), ("lowpass", 1, 337, 5, 3),
                      ("lowpass", 4, 5, 7, 1), ("stress", 3, 7, 5, 2),
                      ("half", 2, 7, 5, 3)]
    for index, (profile, addr, sample, proc, phase) in enumerate(configurations):
        name = f"fir_{profile}_depth{1 << addr}_{sample}_{proc}"
        exe = f"build/{name}.vvp"
        run(["iverilog", "-g2012", "-Wall", "-s", "tb_fir64", "-o", exe,
             f"-Ptb_fir64.FIFO_ADDR_BITS={addr}",
             f'-Ptb_fir64.COEFF_FILE="coefficients/{profile}_q15.hex"', *RTL, "tb/tb_fir64.sv"])
        command = ["vvp", exe, f"+COUNT={count}", f"+PROFILE={profile}",
                   f"+SAMPLE_HALF={sample}", f"+PROC_HALF={proc}", f"+PHASE={phase}"]
        if args.vcd and index == 0:
            command.append("+VCD=build/activity.vcd")
        output = run(command, build / f"{name}.log")
        if output.count("PASS FIR") != 2:
            raise SystemExit(f"Missing completion: {name}")
        results.append({"test": name, "status": "PASS", "samples": count + 128})
    version = subprocess.run(["iverilog", "-V"], text=True, stdout=subprocess.PIPE,
                             stderr=subprocess.STDOUT, check=True).stdout.splitlines()[0]
    summary = {"simulator": version,
               "tests": results, "test_configurations": len(results),
               "fir_outputs_compared": sum(r.get("samples", 0) for r in results)}
    (build / "regression.json").write_text(json.dumps(summary, indent=2) + "\n")
    print(f"PASS: {len(results)} configurations; {summary['fir_outputs_compared']} exact FIR outputs compared")


if __name__ == "__main__":
    main()
