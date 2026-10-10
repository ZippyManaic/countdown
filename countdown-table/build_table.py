#!/usr/bin/env python3
"""
Solve every pool and target with the PyTorch solver and write the answers to one memory-mappable table file
"""

import os
import struct
import sys
import time

import numpy as np

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "countdown-torch"))
import solver  # noqa: E402

from pools import TARGETS, pools  # noqa: E402

# Keep batches near the size the solver is tuned for since its search is not split to fit GPU memory
BATCH = 20_000


def main():
    out_path = sys.argv[1] if len(sys.argv) > 1 else "answers.bin"
    rounds = [(target, pool) for pool in pools() for target in TARGETS]
    values = np.zeros(len(rounds), dtype=np.uint16)
    texts = []
    start = time.perf_counter()
    for first in range(0, len(rounds), BATCH):
        for i, (value, expr) in enumerate(solver.solve_many(rounds[first:first + BATCH]), first):
            values[i] = value
            texts.append(expr.encode("ascii"))
        if first % (50 * BATCH) == 0:
            print(f"{first + BATCH:>9,} of {len(rounds):,} in {time.perf_counter() - start:.0f} s", file=sys.stderr)
    lengths = np.fromiter((len(t) for t in texts), dtype=np.uint32, count=len(texts))
    offsets = np.zeros(len(texts) + 1, dtype=np.uint32)
    np.cumsum(lengths, out=offsets[1:])
    with open(out_path, "wb") as f:
        f.write(b"CDT1" + struct.pack("<I", len(texts)))
        f.write(offsets.tobytes())
        f.write(values.tobytes())
        f.write(b"".join(texts))


if __name__ == "__main__":
    main()
