#!/usr/bin/env python3
"""Prove that no listed target is solvable in Lean, one file per UNSAT job, and audit the axioms of each theorem"""

import argparse
import os
import re
import subprocess
import sys
import tempfile
import threading
from concurrent.futures import ThreadPoolExecutor

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import encode  # noqa: E402
from run_cnf import capped  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
PROJ = os.path.join(HERE, "lean")
LEAN = os.path.expanduser("~/.elan/bin/lean")


def lean_source(label, pool, targets):
    """Return a Lean file proving that no target in the list has an exact solution from the pool"""
    w = encode.width_for(pool, targets)
    ivs = encode.intervals(targets)
    name = re.sub(r"[^A-Za-z0-9_]", "_", label)
    pl = "[" + ", ".join(map(str, pool)) + "]"
    il = "[" + ", ".join(f"({a}, {b})" for a, b in ivs) + "]"
    head = "import CountdownSat\nopen Countdown Countdown.Sat\n\n"
    enc = (f"set_option maxHeartbeats 0 in\nset_option maxRecDepth 1000000 in\n"
           f"theorem enc_{name} : ∀ s0 s1 s2 s3 s4 : Step {w}, Enc {pl} {il} {w} (pick [s0, s1, s2, s3, s4]) = false := by\n"
           f"  enc_unsat\n\n")
    hyps = "(by decide) (by decide) (by decide) (by decide)"
    if len(targets) == 1:
        t = targets[0]
        main = (f"theorem miss_{name} : ¬ Solvable {pl} {t} :=\n"
                f"  not_solvable_of_unsat {hyps} enc_{name} (t := {t}) (by decide)\n\n")
    else:
        tl = "[" + ", ".join(map(str, targets)) + "]"
        main = (f"set_option maxRecDepth 1000000 in\n"
                f"theorem miss_{name} : ∀ t ∈ ({tl} : List Nat), ¬ Solvable {pl} t := by\n"
                f"  have h : ∀ t ∈ ({tl} : List Nat), inNat {il} t = true := by decide +kernel\n"
                f"  exact fun t ht => not_solvable_of_unsat {hyps} enc_{name} (h t ht)\n\n")
    return name, head + enc + main + f"#print axioms miss_{name}\n"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("jobs")
    ap.add_argument("out")
    ap.add_argument("--workers", type=int, default=4)
    ap.add_argument("--cpus", default="24-27")
    ap.add_argument("--keep", default=None)
    ap.add_argument("--tmp", default=None)
    a = ap.parse_args()
    lo, hi = map(int, a.cpus.split("-"))
    free = list(range(lo, hi + 1))[: a.workers]
    lean_path = subprocess.run([os.path.expanduser("~/.elan/bin/lake"), "env", "printenv", "LEAN_PATH"],
                               cwd=PROJ, stdout=subprocess.PIPE, text=True, check=True).stdout.strip()
    os.environ["LEAN_PATH"] = lean_path
    jobs = []
    for line in open(a.jobs):
        label, pool, targets, expect = line.rstrip("\n").split("\t")
        if expect == "unsat":
            jobs.append((label, [int(x) for x in pool.split()], [int(x) for x in targets.split(",")]))
    done = set()
    if os.path.exists(a.out):
        done = {line.split("\t", 1)[0] for line in open(a.out)}
    todo = [j for j in jobs if j[0] not in done]
    tmpdir = a.tmp or tempfile.mkdtemp(prefix="leanrun_")
    os.makedirs(tmpdir, exist_ok=True)
    lock = threading.Lock()
    new = not os.path.exists(a.out) or os.path.getsize(a.out) == 0
    out = open(a.out, "a")
    if new:
        out.write("label\tpool\tntargets\tw\tstatus\tlean_s\tlean_kb\taxioms\n")
        out.flush()

    def work(job):
        label, pool, targets = job
        name, src = lean_source(label, pool, targets)
        fn = os.path.join(tmpdir, name + ".lean")
        with open(fn, "w") as f:
            f.write(src)
        with lock:
            cpu = free.pop()
        try:
            rc, txt, secs, kb = capped(cpu, [LEAN, fn], mem="6G", timeout=3600)
        finally:
            with lock:
                free.append(cpu)
        m = re.search(r"depends on axioms: \[(.*?)\]", txt, re.S)
        axioms = m.group(1).replace("\n", " ") if m else ""
        ax = [x.strip() for x in axioms.split(",") if x.strip()]
        expected = {"propext", "Classical.choice", "Quot.sound"}
        native = [x for x in ax if x not in expected]
        ok_ax = len(native) == 1 and native[0].startswith(f"enc_{name}._native.bv_decide.ax")
        status = "proved" if rc == 0 and "error" not in txt and ok_ax else f"FAILED rc={rc}"
        if status != "proved":
            with open(fn + ".log", "w") as f:
                f.write(txt)
        elif a.keep:
            os.makedirs(a.keep, exist_ok=True)
            os.replace(fn, os.path.join(a.keep, name + ".lean"))
        if os.path.exists(fn) and status == "proved":
            os.remove(fn)
        row = [label, " ".join(map(str, pool)), str(len(targets)), str(encode.width_for(pool, targets)), status,
               str(secs), str(kb), "native" if ok_ax else axioms]
        with lock:
            out.write("\t".join(row) + "\n")
            out.flush()

    with ThreadPoolExecutor(max_workers=a.workers) as ex:
        list(ex.map(work, todo))


if __name__ == "__main__":
    main()
