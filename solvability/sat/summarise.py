#!/usr/bin/env python3
"""Print summary statistics of the pilot result tables in results/"""

import csv
import os
import statistics as st
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
RES = os.path.join(HERE, "results")


def rows(name):
    fn = os.path.join(RES, name)
    if not os.path.exists(fn):
        return []
    # Keep the first row per label since a resumed run may repeat a label
    seen, out = set(), []
    for r in csv.DictReader(open(fn), delimiter="\t"):
        if r["label"] not in seen:
            seen.add(r["label"])
            out.append(r)
    return out


def judge(r):
    """Accept a SAT row whose target is a pool number, which older runner versions marked as a disagreement"""
    if r["agree"] == "NO" and r["status"] == "sat" and r["expr"] == "(leaf)":
        pool = [int(x) for x in r["pool"].split()]
        target = int(r["label"].rsplit("_", 1)[1])
        return "yes" if target in pool else "NO"
    return r["agree"]


def stats(xs):
    if not xs:
        return "-"
    xs = sorted(xs)
    p95 = xs[min(len(xs) - 1, int(0.95 * len(xs)))]
    return f"n={len(xs)} mean={st.mean(xs):.2f} median={st.median(xs):.2f} p95={p95:.2f} max={max(xs):.2f} sum={sum(xs):.0f}"


def cnf_report(name, exclude_batch=True):
    rs = rows(name)
    if not rs:
        return
    print(f"== {name}: {len(rs)} rows")
    agree = [judge(r) for r in rs]
    print("  agree:", {k: agree.count(k) for k in set(agree)})
    checks = [(r["check"], r["check2"]) for r in rs if r["status"] == "unsat"]
    print("  unsat checks:", {k: checks.count(k) for k in set(checks)})
    for status in ("unsat", "sat"):
        g = [r for r in rs if r["status"] == status and not (exclude_batch and r["label"].endswith("_batch"))]
        if not g:
            continue
        print(f"  {status} solve s:", stats([float(r["solve_s"]) for r in g]))
        print(f"  {status} solve MB peak:", stats([int(r["solve_kb"]) / 1024 for r in g]))
        if status == "unsat":
            print("  proof MB:", stats([int(r["proof_bytes"]) / 1e6 for r in g]))
            print("  cake_lpr s:", stats([float(r["check_s"]) for r in g]))
            print("  cake_lpr MB peak:", stats([int(r["check_kb"]) / 1024 for r in g]))
            if any(r["check2"] for r in g):
                print("  lrat-check s:", stats([float(r["check2_s"]) for r in g]))
        print(f"  {status} gen s:", stats([float(r["gen_s"]) for r in g]))
        ws = sorted({int(r["w"]) for r in g})
        print(f"  {status} widths:", ws[0], "to", ws[-1], " clauses:", stats([int(r["clauses"]) for r in g]))
    for r in rs:
        if r["label"].endswith("_batch"):
            print(f"  batch {r['label']}: targets={r['ntargets']} w={r['w']} solve={r['solve_s']}s "
                  f"{int(r['solve_kb']) // 1024}MB proof={int(r['proof_bytes']) / 1e6:.1f}MB "
                  f"cake={r['check_s']}s {int(r['check_kb']) // 1024}MB {r['check']} {r['check2']}")
    bad = [r for r, a in zip(rs, agree) if a != "yes"]
    for r in bad:
        print("  DISAGREEMENT:", r)


def lean_report(name):
    rs = rows(name)
    if not rs:
        return
    print(f"== {name}: {len(rs)} rows")
    print("  status:", {k: [r["status"] for r in rs].count(k) for k in {r["status"] for r in rs}})
    print("  axioms:", {k: [r["axioms"] for r in rs].count(k) for k in {r["axioms"] for r in rs}})
    single = [r for r in rs if r["ntargets"] == "1"]
    if single:
        print("  single lean s:", stats([float(r["lean_s"]) for r in single]))
        print("  single lean MB peak:", stats([int(r["lean_kb"]) / 1024 for r in single]))
    for r in rs:
        if r["ntargets"] != "1":
            print(f"  multi {r['label']}: targets={r['ntargets']} w={r['w']} {r['lean_s']}s "
                  f"{int(r['lean_kb']) // 1024}MB {r['status']}")


if __name__ == "__main__":
    names = sys.argv[1:] or sorted(os.listdir(RES))
    for n in names:
        if not n.endswith(".tsv"):
            continue
        (lean_report if n.startswith("lean_") else cnf_report)(n)
