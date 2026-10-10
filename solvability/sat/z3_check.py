#!/usr/bin/env python3
"""Solve a sample of jobs through the SMT-LIB rendering with Z3 to cross-check our own bit-blaster

Usage: z3_check.py JOBS.tsv COUNT --cpu 24
"""

import argparse
import os
import random
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import encode  # noqa: E402
from run_cnf import capped  # noqa: E402


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("jobs")
    ap.add_argument("count", type=int)
    ap.add_argument("--cpu", default="24")
    ap.add_argument("--seed", type=int, default=7)
    a = ap.parse_args()
    jobs = [line.rstrip("\n").split("\t") for line in open(a.jobs)]
    tmp = tempfile.mkdtemp(prefix="z3check_")
    for label, pool, targets, expect in random.Random(a.seed).sample(jobs, min(a.count, len(jobs))):
        pool = [int(x) for x in pool.split()]
        targets = [int(x) for x in targets.split(",")]
        fn = os.path.join(tmp, "q.smt2")
        open(fn, "w").write(encode.smt_for(pool, targets[0] if len(targets) == 1 else targets))
        rc, out, secs, kb = capped(a.cpu, ["z3", fn], timeout=1800)
        got = out.split("\n", 1)[0].strip()
        print(f"{label}\t{expect}\t{got}\t{secs}\t{'agree' if got == expect else 'DISAGREE'}", flush=True)


if __name__ == "__main__":
    main()
