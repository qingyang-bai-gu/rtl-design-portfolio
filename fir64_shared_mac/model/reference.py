#!/usr/bin/env python3
"""Dependency-free, integer FIR oracle and deterministic vector generator."""
import argparse
import hashlib
import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SEED = 0x13579BDF


def round_away(value):
    return math.floor(value + 0.5) if value >= 0 else math.ceil(value - 0.5)


def coefficients():
    """64-tap Hamming-windowed lowpass, cutoff 0.10 cycles/sample."""
    h = []
    for k in range(64):
        n = k - 31.5
        sinc = math.sin(2 * math.pi * 0.10 * n) / (math.pi * n)
        h.append(sinc * (0.54 - 0.46 * math.cos(2 * math.pi * k / 63)))
    total = sum(h)
    q = [round_away(x * 32768 / total) for x in h]
    correction = 32768 - sum(q)
    assert correction % 2 == 0
    q[31] += correction // 2
    q[32] += correction // 2
    assert q == q[::-1] and sum(q) == 32768
    assert all(-32768 <= c <= 32767 for c in q)
    return q


def stimulus():
    samples = [0] * 4
    samples += [32767] + [0] * 79
    samples += [-32768] + [0] * 79
    samples += [32767] * 96 + [0] * 80
    samples += [-32768] * 96 + [0] * 80
    samples += [32767, -32768] * 64
    samples += [1, -1, 3, -3, 16384, -16384, 0, 32767, -32768] * 8
    state = SEED
    for _ in range(1024):
        state ^= (state << 13) & 0xFFFFFFFF
        state ^= state >> 17
        state ^= (state << 5) & 0xFFFFFFFF
        value = state & 0xFFFF
        samples.append(value if value < 32768 else value - 65536)
    return samples + [0] * 80


def quantize(accumulator):
    magnitude = (abs(accumulator) + 16384) // 32768
    value = -magnitude if accumulator < 0 else magnitude
    return min(32767, max(-32768, value))


def fir(samples, coeffs):
    """Direct convolution, independent of the RTL's circular RAM sequencing."""
    raw = [sum(coeffs[k] * samples[n-k] for k in range(min(n+1, 64)))
           for n in range(len(samples))]
    assert all(-(1 << 37) <= x < (1 << 37) for x in raw)
    return raw, [quantize(x) for x in raw]


def hex_text(values, bits):
    return "".join(f"{v & ((1 << bits)-1):0{(bits+3)//4}x}\n" for v in values)


def artifacts():
    samples = stimulus()
    profiles = {"lowpass": coefficients(), "stress": [-32768] * 64,
                "half": [16384] + [0] * 63}
    files = {"vectors/input.hex": hex_text(samples, 16)}
    manifest = {"seed": f"0x{SEED:08x}", "samples": len(samples), "profiles": {}}
    for name, coeffs in profiles.items():
        raw, outputs = fir(samples, coeffs)
        files[f"coefficients/{name}_q15.hex"] = hex_text(coeffs, 16)
        files[f"vectors/{name}_acc.hex"] = hex_text(raw, 38)
        files[f"vectors/{name}_output.hex"] = hex_text(outputs, 16)
        manifest["profiles"][name] = {
            "coefficient_sum": sum(coeffs), "min_acc": min(raw), "max_acc": max(raw),
            "positive_clips": sum(x >= 32767 * 32768 + 16384 for x in raw),
            "negative_clips": sum(x <= -32768 * 32768 - 16384 for x in raw),
            "positive_ties": sum(x > 0 and x % 32768 == 16384 for x in raw),
            "negative_ties": sum(x < 0 and (-x) % 32768 == 16384 for x in raw),
        }
    manifest["sha256"] = {name: hashlib.sha256(data.encode()).hexdigest()
                           for name, data in sorted(files.items())}
    files["vectors/manifest.json"] = json.dumps(manifest, indent=2) + "\n"
    return files


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="verify checked-in vectors without writing")
    parser.add_argument("--out", type=Path, default=ROOT)
    args = parser.parse_args()
    for name, data in artifacts().items():
        path = args.out / name
        if args.check:
            if not path.exists() or path.read_text() != data:
                raise SystemExit(f"Vector mismatch: {path}; run make vectors")
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(data)
    print(f"{'Verified' if args.check else 'Generated'} {len(stimulus())} samples, three coefficient profiles")


if __name__ == "__main__":
    main()
