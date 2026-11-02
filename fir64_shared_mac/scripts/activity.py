#!/usr/bin/env python3
"""Count known-to-known bit transitions in a VCD; this is NOT a power model."""
import argparse
import json
from pathlib import Path


def analyze(path):
    scope, signals, values, counts = [], {}, {}, {}
    time, timescale = 0, "unspecified"
    header = True
    with path.open() as handle:
        for raw in handle:
            line = raw.strip()
            if header:
                words = line.split()
                if line.startswith("$scope"):
                    scope.append(words[2])
                elif line.startswith("$upscope"):
                    scope.pop()
                elif line.startswith("$var"):
                    _, kind, width, code, ref, *rest = words
                    name = ".".join(scope + [ref])
                    if code not in signals:
                        signals[code] = {"width": int(width), "names": []}
                        counts[code] = 0
                    signals[code]["names"].append(name)
                elif line.startswith("$timescale"):
                    timescale = line.removeprefix("$timescale").replace("$end", "").strip()
                    if not timescale:
                        timescale = next(handle).strip()
                elif line.startswith("$enddefinitions"):
                    header = False
                continue
            if not line or line[0] == "$":
                continue
            if line[0] == "#":
                time = int(line[1:])
                continue
            if line[0].lower() == "b":
                value, code = line[1:].split()
                value = value.lower()
            elif line[0].lower() in "01xz":
                value, code = line[0].lower(), line[1:]
            else:
                continue
            if code not in signals:
                continue
            width = signals[code]["width"]
            fill = value[0] if value[0] in "xz" else "0"
            value = value.rjust(width, fill)
            previous = values.get(code, "x" * width)
            counts[code] += sum(a in "01" and b in "01" and a != b
                                for a, b in zip(previous, value))
            values[code] = value
    ranking = [{**signals[code], "bit_transitions": count} for code, count in counts.items()]
    ranking.sort(key=lambda item: item["bit_transitions"], reverse=True)
    return {"kind": "RTL switching activity; not watts or a gate-level power estimate",
            "vcd_timescale": timescale, "duration_ticks": time,
            "unique_signal_ids": len(signals), "known_bit_transitions": sum(counts.values()),
            "top_signals": ranking[:25],
            "caveats": "Aliases counted once. X/Z transitions ignored. Entire test includes resets and stalls."}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("vcd", type=Path)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    result = analyze(args.vcd)
    args.out.write_text(json.dumps(result, indent=2) + "\n")
    print(f"Activity: {result['known_bit_transitions']} known bit transitions; {args.out}")


if __name__ == "__main__":
    main()
