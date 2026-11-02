"""Independent integer reference for aligned paired AXI bursts (no RTL dependencies)."""
import argparse
import random
from pathlib import Path


def config(address_width=32, data_width=128, maximum=16):
    if not 12 <= address_width <= 64:
        raise ValueError("address width")
    if not 8 <= data_width <= 1024 or data_width % 8:
        raise ValueError("data width")
    beat = data_width // 8
    if beat & (beat - 1) or not 1 <= maximum <= 256:
        raise ValueError("beat size or maximum")
    return beat


def legal(src, dst, length, address_width=32, data_width=128):
    beat = config(address_width, data_width)
    limit = 2 ** address_width
    return (length > 0 and min(src, dst) >= 0
            and (src | dst | length) % beat == 0
            and src + length <= limit and dst + length <= limit
            and (src + length <= dst or dst + length <= src))


def plan(src, dst, length, address_width=32, data_width=128, maximum=16):
    beat = config(address_width, data_width, maximum)
    if not legal(src, dst, length, address_width, data_width):
        raise ValueError("descriptor")
    chunks = []
    while length:
        # Divide byte room rather than mirroring a hardware scan or bit slice.
        count = min(length // beat, maximum,
                    (4096 - src % 4096) // beat, (4096 - dst % 4096) // beat)
        chunks.append((src, dst, count))
        src += count * beat
        dst += count * beat
        length -= count * beat
    return chunks


def vectors(path, count=6927):
    rng = random.Random(0xA414D00D)
    rows = [(0, 0x8000, 16), (0xFF0, 0x8FE0, 1024), (0, 0xFFFFFFF0, 16)]
    while len(rows) < count:
        src = rng.randrange(0, 0x4000) * 16
        dst = rng.randrange(0x8000, 0xC000) * 16
        rows.append((src, dst, 16 * rng.randint(1, 1024)))
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open('w') as out:
        for src, dst, length in rows:
            beats = plan(src, dst, length)[0][2]
            out.write(f"{src:x} {dst:x} {length:x} {beats:x}\n")
    return len(rows)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    print(f"wrote {vectors(args.output)} planner vectors")
