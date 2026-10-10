"""Probe whether Z3's proof output for one no-solution instance is usable"""

import time

import z3

z3.set_param("proof", True)
z3.set_param("memory_max_size", 3000)

from common import Program, write_json  # noqa: E402


def main():
    pool, t = (1, 1, 2, 2, 3, 25), 179
    P = Program(pool)
    s = z3.Solver()
    s.set("timeout", 600_000)
    s.add(P.cs)
    s.add(P.reaches(t))
    t0 = time.time()
    r = s.check()
    out = {"pool": pool, "target": t, "result": str(r), "time": time.time() - t0}
    if r == z3.unsat:
        pr = s.proof()
        text = pr.sexpr()
        rules = {}
        # Count proof rule names by scanning the printed proof
        for name in ("th-lemma", "unit-resolution", "lemma", "hypothesis", "rewrite", "mp", "asserted"):
            rules[name] = text.count("(" + name + " ") + text.count("(" + name + "\n")
        out.update({"proof_chars": len(text), "rule_counts": rules,
                    "arith_th_lemmas_with_nla": text.count("arith") })
        with open("results/proof_179.txt", "w") as f:
            f.write(text[:200000])
    write_json("proof_probe.json", out)
    print(out, flush=True)


if __name__ == "__main__":
    main()
