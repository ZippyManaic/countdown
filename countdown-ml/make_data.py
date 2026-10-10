#!/usr/bin/env python3
"""
Deal random rounds, solve them with the PyTorch solver and save them as training tokens
"""

import os
import random
import sys
import time

import torch

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "countdown-torch"))
import solver  # noqa: E402
from countdown import generate_round  # noqa: E402

from tokens import ANSWER_LEN, PAD, PROMPT_LEN, answer, prompt  # noqa: E402

BATCH = 20_000


def main():
    count, seed, out_path = int(sys.argv[1]), int(sys.argv[2]), sys.argv[3]
    random.seed(seed)
    data = torch.full((count, PROMPT_LEN + ANSWER_LEN), PAD, dtype=torch.uint8)
    start = time.perf_counter()
    for first in range(0, count, BATCH):
        rounds = [generate_round() for _ in range(min(BATCH, count - first))]
        for i, ((target, pool), (_, expr)) in enumerate(zip(rounds, solver.solve_many(rounds)), first):
            row = prompt(target, pool) + answer(expr, pool)
            data[i, :len(row)] = torch.tensor(row, dtype=torch.uint8)
        print(f"{first + len(rounds):,} rounds in {time.perf_counter() - start:.0f} s", file=sys.stderr)
    torch.save(data, out_path)


if __name__ == "__main__":
    main()
