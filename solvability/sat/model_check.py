#!/usr/bin/env python3
"""Check that every CaDiCaL model of the Python CNF satisfies the Lean definition Enc, as a cross-check of the two encoders

Usage: model_check.py JOBS.tsv... --cpu 24
"""

import argparse
import os
import re
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import encode  # noqa: E402
from run_cnf import capped  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
PROJ = os.path.join(HERE, "lean")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("jobs", nargs="+")
    ap.add_argument("--cpu", default="24")
    ap.add_argument("--out", default=os.path.join(HERE, "results", "model_check.txt"))
    a = ap.parse_args()
    tmp = tempfile.mkdtemp(prefix="modelcheck_")
    lines = ["import CountdownSat", "open Countdown.Sat", ""]
    n = 0
    for jf in a.jobs:
        for line in open(jf):
            label, pool, targets, expect = line.rstrip("\n").split("\t")
            if expect != "sat":
                continue
            pool = [int(x) for x in pool.split()]
            targets = [int(x) for x in targets.split(",")]
            w = encode.width_for(pool, targets)
            cnf, varmap = encode.cnf_for(pool, targets[0] if len(targets) == 1 else targets, w)
            fn = os.path.join(tmp, "m.cnf")
            open(fn, "w").write(cnf)
            rc, out, _, _ = capped(a.cpu, ["cadical", "-q", fn])
            assert rc == 10, (label, rc)
            model = {}
            for ln in out.splitlines():
                if ln.startswith("v "):
                    for x in map(int, ln[2:].split()):
                        if x:
                            model[abs(x)] = x > 0
            val = lambda name: sum(1 << i for i, v in enumerate(varmap[name]) if v is not None and model.get(v, False))
            steps = []
            for k in range(encode.NSTEPS):
                b = lambda x: "true" if val(x) else "false"
                steps.append(f"⟨{b(f'act{k}')}, BitVec.ofNat 4 {val(f'sa{k}')}, BitVec.ofNat 4 {val(f'sb{k}')}, "
                             f"{b(f'opm{k}')}, {b(f'opi{k}')}, BitVec.ofNat {w} {val(f'xa{k}')}, "
                             f"BitVec.ofNat {w} {val(f'xb{k}')}, BitVec.ofNat {w} {val(f'r{k}')}⟩")
            ivs = "[" + ", ".join(f"({x}, {y})" for x, y in encode.intervals(targets)) + "]"
            moved = "[" + ", ".join(f"({x + 1000}, {y + 1000})" for x, y in encode.intervals(targets)) + "]"
            pl = "[" + ", ".join(map(str, pool)) + "]"
            st = "(pick [" + ", ".join(steps) + "])"
            # Expect true for the model and false once the target set is moved out of reach
            lines.append(f"#eval (Enc {pl} {ivs} {w} {st}, Enc {pl} {moved} {w} {st})")
            n += 1
    src = os.path.join(tmp, "ModelCheck.lean")
    open(src, "w").write("\n".join(lines) + "\n")
    lean_path = subprocess.run([os.path.expanduser("~/.elan/bin/lake"), "env", "printenv", "LEAN_PATH"],
                               cwd=PROJ, stdout=subprocess.PIPE, text=True, check=True).stdout.strip()
    os.environ["LEAN_PATH"] = lean_path
    rc, out, secs, kb = capped(a.cpu, [os.path.expanduser("~/.elan/bin/lean"), src], timeout=3600)
    results = re.findall(r"\((true|false), (true|false)\)", out)
    good = sum(1 for x, y in results if x == "true" and y == "false")
    msg = f"models {n}, Lean evaluations {len(results)}, (true, false) {good}, rc {rc}, {secs} s"
    print(msg)
    open(a.out, "w").write(msg + "\n")


if __name__ == "__main__":
    main()
