"""
Deal rounds with countdown.py's own dealer and count how often the checker's tables say there is no exact answer
"""

import importlib.util
import math
import os
import random
import sys
from fractions import Fraction

from common import DATA, ROOT, LARGE, deal_probability, load_checker, load_pools

SEED = 20261010
ROUNDS = 1_000_000


def wilson(k, n, z=1.959963984540054):
    p = k / n
    centre = (p + z * z / (2 * n)) / (1 + z * z / n)
    half = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / (1 + z * z / n)
    return centre - half, centre + half


def main():
    spec = importlib.util.spec_from_file_location("dealer", os.path.join(ROOT, "countdown.py"))
    dealer = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(dealer)
    checker = load_checker()
    pools = load_pools()
    exact = sum(deal_probability(p) * len(checker[p][2]) for p in pools) / 900
    exact_by = {e: 2 * sum(deal_probability(p) * len(checker[p][2]) for p in pools
                           if sum(x in LARGE for x in p) == e) / 900 for e in (1, 2)}

    random.seed(SEED)
    misses, seen = 0, {1: [0, 0], 2: [0, 0]}
    for _ in range(ROUNDS):
        target, pool = dealer.generate_round()
        missed = target in checker[tuple(sorted(pool))][2]
        misses += missed
        e = sum(x in LARGE for x in pool)
        seen[e][0] += 1
        seen[e][1] += missed
    lo, hi = wilson(misses, ROUNDS)
    print(f"dealt {ROUNDS:,} rounds with countdown.generate_round under random.seed({SEED})")
    print(f"no exact answer: {misses:,} = {misses / ROUNDS:.6f}, 95% Wilson interval [{lo:.6f}, {hi:.6f}]")
    p = float(exact)
    z = (misses - ROUNDS * p) / math.sqrt(ROUNDS * p * (1 - p))
    print(f"exact value {p:.6f} {'inside' if lo <= p <= hi else 'OUTSIDE'} the interval, z = {z:+.2f}")
    for e in (1, 2):
        n, k = seen[e]
        lo, hi = wilson(k, n)
        print(f"  {e} large: {k:,} of {n:,} = {k / n:.6f}, interval [{lo:.6f}, {hi:.6f}], exact {float(exact_by[e]):.6f}")

    # Count the benchmark set's misses from its reference answers and check them against the tables
    rounds = [list(map(int, line.split())) for line in open(os.path.join(ROOT, "bench", "data", "rounds10k.txt"))]
    refs = [int(line.split("\t")[0]) for line in open(os.path.join(ROOT, "bench", "data", "ref10k.tsv"))]
    assert len(rounds) == len(refs) == 10_000
    ref_miss = table_miss = disagree = 0
    for (target, *pool), value in zip(rounds, refs):
        a = value != target
        b = target in checker[tuple(sorted(pool))][2]
        ref_miss += a
        table_miss += b
        disagree += a != b
        if b and abs(value - target) != checker[tuple(sorted(pool))][2][target]:
            disagree += 1
    lo, hi = wilson(ref_miss, 10_000)
    print(f"bench/data/rounds10k.txt: {ref_miss} misses by ref10k.tsv, {table_miss} by the checker tables, "
          f"{disagree} disagreements (status or distance); rate {ref_miss / 10_000:.4f}, interval [{lo:.4f}, {hi:.4f}]")
    z = (ref_miss - 10_000 * p) / math.sqrt(10_000 * p * (1 - p))
    print(f"  z against the exact value = {z:+.2f}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
