"""Check the Section sec:cats largest values for two pools in Z3's integer theory"""

import time

import z3

from common import Program, reachable, solver, timed_check, write_json

CLAIMS = [((10, 10, 25, 50, 75, 100), 937_500_000), ((10, 10, 12, 37, 62, 87), 239_493_600)]


def B(pool):
    """Return B([n]) of Proposition prop:max by the split recursion in plain Python"""
    n = len(pool)
    memo = {1 << i: pool[i] for i in range(n)}
    for mask in range(1, 1 << n):
        if mask in memo:
            continue
        best, sub = 0, (mask - 1) & mask
        while sub:
            if sub < mask ^ sub:
                u, v = memo[sub], memo[mask ^ sub]
                best = max(best, u * v, u + v)
            sub = (sub - 1) & mask
        memo[mask] = best
    return memo[(1 << n) - 1]


def main():
    out = []
    for pool, claim in CLAIMS:
        row = {"pool": pool, "claim": claim, "B": B(pool), "python_max": max(reachable(pool))}
        # Attain the claimed value with a decoded and independently evaluated witness
        P = Program(pool)
        s = solver(timeout_ms=360_000)
        s.add(*P.cs, P.reaches(claim))
        r, t = timed_check(s)
        row.update({"attained": str(r), "attained_time": t})
        if r == z3.sat:
            steps, exprs = P.decode(s.model(), claim)
            node = P.check_witness(steps, claim)
            row.update({"witness": exprs[node] if node is not None else None, "witness_ok": node is not None})
        # Exceed the claimed value with any node to show no legal expression does
        P = Program(pool, name="q")
        s = solver(timeout_ms=360_000)
        s.add(*P.cs, z3.Or([v > claim for v in P.val]))
        r, t = timed_check(s)
        row.update({"exceeded": str(r), "exceeded_time": t})
        print(row, flush=True)
        out.append(row)
    write_json("cats_max.json", out)


if __name__ == "__main__":
    main()
