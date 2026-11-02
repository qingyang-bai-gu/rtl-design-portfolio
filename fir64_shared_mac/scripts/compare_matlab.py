#!/usr/bin/env python3
"""Compare MATLAB-generated coefficients and vectors against the integer oracle."""
import argparse
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "model"))
from reference import artifacts  # noqa: E402


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path)
    args = parser.parse_args()
    count = 0
    for name, expected in artifacts().items():
        if name.endswith(".json"):
            continue
        path = args.directory / name
        if not path.is_file() or path.read_text().lower() != expected:
            raise SystemExit(f"MATLAB/Python mismatch or missing file: {path}")
        count += 1
    print(f"PASS: all {count} MATLAB coefficient/vector files match the Python oracle")


if __name__ == "__main__":
    main()
