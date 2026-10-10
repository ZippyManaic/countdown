#!/usr/bin/env python3
"""
Run the real C solver under sanitisers on every cats and nasty-cats pool and check a sample against the Python reference
"""

import argparse
import itertools
import random
import subprocess
import sys
from collections import Counter
from fractions import Fraction
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parents[2]))
import countdown  # noqa: E402

SETS = {"cats": [25, 50, 75, 100], "nasty-cats": [12, 37, 62, 87]}
# Use a target above every reachable value so every pool builds all its subsets and scans the whole pool
STRESS_TARGET = 1_000_000_000


def pools(large):
    """
    Yield every pool with up to two of each small number and up to four distinct large numbers in ascending order
    """
    smalls = [n for n in range(1, 11) for _ in range(2)]
    seen = set()
    for k in range(5):
        for big in itertools.combinations(large, k):
            for small in itertools.combinations(smalls, 6 - k):
                pool = tuple(sorted(small + big))
                if pool not in seen:
                    seen.add(pool)
                    yield list(pool)


def evaluate(expr, pool):
    """
    Evaluate an answer under Countdown rules and return its value and the numbers it uses or raise on an illegal step
    """
    tokens = expr.replace("(", " ( ").replace(")", " ) ").split()
    used = []

    def atom(i):
        if tokens[i] == "(":
            v, i = binary(i + 1)
            assert tokens[i] == ")"
            return v, i + 1
        used.append(int(tokens[i]))
        return int(tokens[i]), i + 1

    def binary(i):
        v, i = atom(i)
        while i < len(tokens) and tokens[i] in "+-*/":
            op = tokens[i]
            w, i = atom(i + 1)
            if op == "+":
                v = v + w
            elif op == "-":
                v = v - w
            elif op == "*":
                v = v * w
            else:
                assert w != 0 and v % w == 0, f"inexact division in {expr}"
                v = v // w
            assert v > 0, f"non-positive step in {expr}"
        return v, i

    v, i = binary(0)
    assert i == len(tokens)
    assert not Counter(used) - Counter(pool), f"{expr} uses numbers outside {pool}"
    return v, len(used)


def run(binary, rounds):
    text = "".join(f"{t} {' '.join(map(str, p))}\n" for t, p in rounds)
    out = subprocess.run([binary], input=text, capture_output=True, text=True)
    if out.returncode != 0:
        sys.exit(f"{binary} failed with {out.returncode}:\n{out.stderr[-4000:]}")
    lines = out.stdout.splitlines()
    assert len(lines) == len(rounds), "solver stopped early"
    return [(int(v), e) for v, e in (line.split("\t") for line in lines)]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--build", default=str(HERE / "build"))
    parser.add_argument("--sample", type=int, default=150)
    args = parser.parse_args()
    rng = random.Random(2026)
    failures = 0
    for mode, large in SETS.items():
        every = list(pools(large))
        rounds = []
        for pool in every:
            rounds.append((rng.randint(100, 999), pool))
            rounds.append((STRESS_TARGET, pool))
            # Deal the pool in reverse too so a different order reaches the same code
            rounds.append((rng.randint(100, 999), pool[::-1]))
        answers = run(f"{args.build}/driver-san", rounds)
        for (t, p), (v, e) in zip(rounds, answers):
            got, _ = evaluate(e, p)
            if got != v:
                print(f"{mode}: {t} {p}: expression {e} is {got} not {v}")
                failures += 1
        print(f"{mode}: {len(every)} pools, {len(rounds)} rounds under ASan and UBSan, every expression legal and equal to its value")

        # Compare distance and number count with the Python reference on every four-large pool plus a random sample
        four = [p for p in every if sum(n in large for n in p) == 4]
        sample = four + rng.sample(every, args.sample)
        checks = [(rng.randint(100, 999), p) for p in sample] + [(STRESS_TARGET, p) for p in four]
        mismatches = 0
        for (t, p), (v, e) in zip(checks, run(f"{args.build}/driver", checks)):
            rv, re = countdown.solve(t, p)
            _, used = evaluate(e, p)
            _, ref_used = evaluate(re, p)
            if abs(t - v) != abs(t - rv) or used != ref_used:
                print(f"{mode}: {t} {p}: C gives {e} = {v} but reference gives {re} = {rv}")
                mismatches += 1
        failures += mismatches
        print(f"{mode}: {len(checks)} rounds against countdown.py, {mismatches} differ in distance or numbers used")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
