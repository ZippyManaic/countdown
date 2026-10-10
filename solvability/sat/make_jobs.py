#!/usr/bin/env python3
"""Write the pilot job lists into jobs/ from the study's miss tables"""

import os
import random

HERE = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.join(HERE, "..", "data")
JOBS = os.path.join(HERE, "jobs")


def load(name):
    """Return a dict from pool string to the list of missed targets"""
    out = {}
    for line in open(os.path.join(DATA, name)).readlines()[1:]:
        pool, count, ts = line.rstrip("\n").split("\t")
        out[pool] = [int(t) for t in ts.split(",")] if int(count) else []
    return out


def reach_by_size(pool):
    """Map each value to the fewest pool numbers needed to reach it under the game's rules"""
    n = len(pool)
    vals = {}
    for m in range(1, 1 << n):
        if m & (m - 1) == 0:
            vals[m] = {pool[m.bit_length() - 1]}
            continue
        s = set()
        sub = (m - 1) & m
        while sub:
            other = m ^ sub
            if sub < other:
                for a in vals[sub]:
                    for b in vals[other]:
                        s.add(a + b)
                        s.add(a * b)
                        if a > b:
                            s.add(a - b)
                        if b > a:
                            s.add(b - a)
                        if a % b == 0:
                            s.add(a // b)
                        if b % a == 0:
                            s.add(b // a)
            sub = (sub - 1) & m
        vals[m] = s
    best = {}
    for m, s in vals.items():
        k = bin(m).count("1")
        for v in s:
            if v not in best or k < best[v]:
                best[v] = k
    return best


def write(name, rows):
    with open(os.path.join(JOBS, name), "w") as f:
        for r in rows:
            f.write("\t".join(r) + "\n")
    print(name, len(rows))


def main():
    os.makedirs(JOBS, exist_ok=True)
    std, cats, nasty = load("misses.tsv"), load("misses_cats.tsv"), load("misses_nasty.tsv")

    # Take every target of the worst standard pool and add one batched call for its misses
    worst = "1 1 2 2 3 25"
    rows = [(f"worst_{t}", worst, str(t), "unsat" if t in std[worst] else "sat") for t in range(100, 1000)]
    rows.append(("worst_batch", worst, ",".join(map(str, std[worst])), "unsat"))
    write("p1_worst.tsv", rows)

    # Take target 967 against every standard pool that misses it
    rows = [(f"t967_{p.replace(' ', '_')}", p, "967", "unsat") for p, ts in std.items() if 967 in ts]
    write("p2_967.tsv", rows)

    # Take every target of the widest-valued cats pool and add one batched call for its misses
    cp = "1 1 25 50 75 100"
    rows = [(f"cats_{t}", cp, str(t), "unsat" if t in cats[cp] else "sat") for t in range(100, 1000)]
    rows.append(("cats_batch", cp, ",".join(map(str, cats[cp])), "unsat"))
    write("p3_cats.tsv", rows)

    # Take barely solvable targets that need all six numbers from a fixed random sample of pools
    rng = random.Random(4)
    rows = []
    for p in rng.sample(sorted(std), 60):
        pool = [int(x) for x in p.split()]
        best = reach_by_size(pool)
        six = [t for t in range(100, 1000) if best.get(t) == 6]
        if six:
            t = rng.choice(six)
            rows.append((f"hard_{p.replace(' ', '_')}_{t}", p, str(t), "sat"))
        if len(rows) == 20:
            break
    write("p4_hard.tsv", rows)

    # Take one batched call per pool for random samples of pools with misses to extrapolate from
    for name, table, k in (("std", std, 300), ("cats", cats, 100), ("nasty", nasty, 100)):
        pools = sorted(p for p, ts in table.items() if ts)
        rows = [(f"batch_{name}_{p.replace(' ', '_')}", p, ",".join(map(str, table[p])), "unsat")
                for p in random.Random(5).sample(pools, k)]
        write(f"p5_batch_{name}.tsv", rows)


if __name__ == "__main__":
    main()
