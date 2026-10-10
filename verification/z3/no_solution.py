"""Decide exact solvability with Z3 in unbounded integer arithmetic and compare with the exhaustive tables"""

import argparse
import json
import os
import random
import time

import z3

from common import OUT, Program, read_misses, reachable, solver, timed_check


def instances(job):
    """Return the (pool, target, expected solvable) list for a job"""
    if job == "worst":
        misses = read_misses("misses.tsv")
        pool = (1, 1, 2, 2, 3, 25)
        return [(pool, t, t not in misses[pool]) for t in range(100, 1000)]
    if job == "t967":
        misses = read_misses("misses.tsv")
        pools = sorted(p for p, ts in misses.items() if 967 in ts)
        # Take a fixed pseudo-random sample so the run is reproducible
        sample = random.Random(967).sample(pools, 100)
        return [(p, 967, False) for p in sorted(sample)]
    if job == "cats4":
        misses = read_misses("misses_cats.tsv")
        pool = (1, 1, 25, 50, 75, 100)
        return [(pool, t, t not in misses[pool]) for t in range(100, 1000)]
    raise ValueError(job)


def run_one(pool, t, timeout_ms):
    """Ask whether some legal expression over pool equals t and check any witness independently"""
    P = Program(pool)
    s = solver(timeout_ms=timeout_ms)
    s.add(P.cs)
    s.add(P.reaches(t))
    r, dt = timed_check(s)
    row = {"pool": list(pool), "target": t, "result": str(r), "time": dt}
    if r == z3.sat:
        steps, exprs = P.decode(s.model(), t)
        node = P.check_witness(steps, t)
        row["witness"] = exprs[node] if node is not None else None
        row["witness_ok"] = node is not None
    return row


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("job", choices=["worst", "t967", "cats4"])
    ap.add_argument("--shard", type=int, default=0)
    ap.add_argument("--shards", type=int, default=1)
    ap.add_argument("--timeout", type=int, default=300, help="seconds per instance")
    a = ap.parse_args()
    todo = instances(a.job)[a.shard::a.shards]
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, f"no_solution_{a.job}_{a.shard}of{a.shards}.jsonl")
    # Recompute reachability in plain Python as a further independent reference for each pool
    ref = {}
    with open(path, "w") as f:
        for pool, t, expect in todo:
            if pool not in ref:
                ref[pool] = reachable(pool)
            row = run_one(pool, t, a.timeout * 1000)
            row["expected_solvable"] = expect
            row["python_solvable"] = t in ref[pool]
            f.write(json.dumps(row) + "\n")
            f.flush()
            print(row["pool"], t, row["result"], f"{row['time']:.2f}", flush=True)


if __name__ == "__main__":
    main()
