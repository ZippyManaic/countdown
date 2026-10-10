#!/usr/bin/env python3
"""Solve encoded instances from a job list with CaDiCaL, check every UNSAT proof with cake_lpr and decode every model"""

import argparse
import os
import re
import subprocess
import sys
import tempfile
import threading
import time
from concurrent.futures import ThreadPoolExecutor

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import encode  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
CAKE = os.path.join(HERE, "tools/cake_lpr/cake_lpr")
LRATCHECK = os.path.join(HERE, "tools/drat-trim/lrat-check")
MEM = "6G"
TIMEOUT = 1800
# Name a systemd slice to hold every job so one cap can limit the memory of the whole run
SLICE = None


def capped(cpu, argv, mem=MEM, timeout=TIMEOUT):
    """Run a command under a memory cap, a timeout and a CPU pin and return its status, output, seconds and peak KB"""
    cmd = ["systemd-run", "--user", "--scope", "-q", *([f"--slice={SLICE}"] if SLICE else []),
           "-p", f"MemoryMax={mem}", "-p", "MemorySwapMax=0", "timeout", str(timeout), "taskset", "-c", str(cpu),
           "/usr/bin/time", "-f", "@@TIME %e %M", *argv]
    p = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    m = re.search(r"@@TIME ([\d.]+) (\d+)", p.stderr)
    secs, kb = (float(m.group(1)), int(m.group(2))) if m else (float("nan"), -1)
    rc = p.returncode
    # Recover the child's exit status from GNU time's report when it exits non-zero
    m2 = re.search(r"Command exited with non-zero status (\d+)", p.stderr)
    if m2:
        rc = int(m2.group(1))
    if "Command terminated by signal" in p.stderr:
        rc = -int(re.search(r"signal (\d+)", p.stderr).group(1))
    return rc, p.stdout + p.stderr, secs, kb


def run_job(job, cpu, tmpdir, lrat_check):
    label, pool, targets, expect = job
    t0 = time.time()
    w = encode.width_for(pool, targets)
    cnf, varmap = encode.cnf_for(pool, targets if len(targets) > 1 else targets[0], w)
    gen = time.time() - t0
    nvars, ncls = map(int, cnf.split("\n", 1)[0].split()[2:4])
    base = os.path.join(tmpdir, re.sub(r"[^A-Za-z0-9_.-]", "_", label))
    with open(base + ".cnf", "w") as f:
        f.write(cnf)
    proof = base + (".lrat.txt" if lrat_check else ".lrat")
    argv = ["cadical", "-q", "--lrat", base + ".cnf", proof]
    if lrat_check:
        argv.insert(2, "--binary=false")
    rc, out, solve_s, solve_kb = capped(cpu, argv)
    status = {10: "sat", 20: "unsat"}.get(rc, f"error{rc}")
    res = dict(label=label, pool=" ".join(map(str, pool)), ntargets=len(targets), w=w, vars=nvars,
               clauses=ncls, gen_s=round(gen, 3), status=status, solve_s=solve_s, solve_kb=solve_kb,
               proof_bytes=0, check="", check_s=0.0, check_kb=0, check2="", check2_s=0.0, expr="", agree="")
    if status == "unsat":
        res["proof_bytes"] = os.path.getsize(proof)
        rc2, out2, cs, ckb = capped(cpu, [CAKE, "--CML_HEAP_SIZE=1024", base + ".cnf", proof])
        if "s VERIFIED UNSAT" not in out2:
            # Retry with a larger heap since cake_lpr stops when its heap is exhausted
            rc2, out2, cs, ckb = capped(cpu, [CAKE, "--CML_HEAP_SIZE=5000", base + ".cnf", proof])
        res["check"] = "verified" if "s VERIFIED UNSAT" in out2 else "FAILED"
        res["check_s"], res["check_kb"] = cs, ckb
        if lrat_check:
            rc3, out3, cs3, _ = capped(cpu, [LRATCHECK, base + ".cnf", proof])
            res["check2"] = "verified" if re.search(r"^c VERIFIED", out3, re.M) else "FAILED"
            res["check2_s"] = cs3
        res["agree"] = "yes" if expect == "unsat" and res["check"] == "verified" else "NO"
    elif status == "sat":
        model = {}
        for line in out.splitlines():
            if line.startswith("v "):
                for x in line[2:].split():
                    x = int(x)
                    if x:
                        model[abs(x)] = x > 0
        expr = encode.decode(model, varmap, pool, targets)
        res["expr"] = expr or "(leaf)"
        try:
            # Accept a bare pool number as the expression when it is itself a target
            ok = encode.evaluate(expr, pool) in targets if expr else any(v in targets for v in pool)
        except (AssertionError, ValueError):
            ok = False
        res["agree"] = "yes" if expect == "sat" and ok else "NO"
    else:
        res["agree"] = "NO"
    for fn in (base + ".cnf", proof):
        if os.path.exists(fn):
            os.remove(fn)
    return res


COLS = ["label", "pool", "ntargets", "w", "vars", "clauses", "gen_s", "status", "solve_s", "solve_kb",
        "proof_bytes", "check", "check_s", "check_kb", "check2", "check2_s", "expr", "agree"]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("jobs")
    ap.add_argument("out")
    ap.add_argument("--workers", type=int, default=6)
    ap.add_argument("--cpus", default="24-29")
    ap.add_argument("--lrat-check", action="store_true")
    ap.add_argument("--tmp", default=None)
    ap.add_argument("--slice", default=None)
    a = ap.parse_args()
    global SLICE
    SLICE = a.slice
    lo, hi = map(int, a.cpus.split("-"))
    cpus = list(range(lo, hi + 1))
    jobs = []
    for line in open(a.jobs):
        if not line.strip() or line.startswith("#"):
            continue
        label, pool, targets, expect = line.rstrip("\n").split("\t")
        jobs.append((label, [int(x) for x in pool.split()], [int(x) for x in targets.split(",")], expect))
    done = set()
    if os.path.exists(a.out):
        for line in open(a.out):
            done.add(line.split("\t", 1)[0])
    todo = [j for j in jobs if j[0] not in done]
    free = list(cpus[: a.workers])
    lock = threading.Lock()
    tmpdir = a.tmp or tempfile.mkdtemp(prefix="satrun_")
    os.makedirs(tmpdir, exist_ok=True)
    new = not os.path.exists(a.out) or os.path.getsize(a.out) == 0
    out = open(a.out, "a")
    if new:
        out.write("\t".join(COLS) + "\n")
        out.flush()

    def work(job):
        with lock:
            cpu = free.pop()
        try:
            res = run_job(job, cpu, tmpdir, a.lrat_check)
        finally:
            with lock:
                free.append(cpu)
        with lock:
            out.write("\t".join(str(res[c]) for c in COLS) + "\n")
            out.flush()
        return res

    with ThreadPoolExecutor(max_workers=a.workers) as ex:
        for _ in ex.map(work, todo):
            pass


if __name__ == "__main__":
    main()
