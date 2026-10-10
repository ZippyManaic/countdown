"""Check how Proposition prop:prime is used: no legal final multiplication makes a prime target in 100 to 999"""

import z3

from common import Program, reachable, solver, timed_check, write_json


def is_prime(t):
    """Return whether t is prime by trial division"""
    return t > 1 and all(t % d for d in range(2, int(t**0.5) + 1))


def main():
    primes = [t for t in range(100, 1000) if is_prime(t)]
    x, y = z3.Ints("x y")
    generic = []
    for t in primes:
        s = solver(timeout_ms=60_000)
        # Ask for a legal multiplication x * y with x >= y >= 2 giving t
        s.add(x >= y, y >= 2, x * y == t)
        r, dt = timed_check(s)
        generic.append({"t": t, "result": str(r), "time": dt})
    # Ask in context for the worst pool that a reachable prime is never made by a final multiplication
    pool = (1, 1, 2, 2, 3, 25)
    reach = reachable(pool)
    sample = [t for t in primes if t in reach][:5]
    in_pool = []
    for t in sample:
        P = Program(pool)
        s = solver(timeout_ms=300_000)
        s.add(P.cs)
        s.add(z3.Or([z3.And(P.active[k], P.val[P.n + k] == t, P.op[k] == 2) for k in range(P.steps)]))
        r, dt = timed_check(s)
        s2 = solver(timeout_ms=300_000)
        P2 = Program(pool, name="w")
        s2.add(*P2.cs, P2.reaches(t))
        r2, dt2 = timed_check(s2)
        in_pool.append({"t": t, "final_multiplication": str(r), "time": dt, "reachable_at_all": str(r2), "time_reach": dt2})
    out = {"primes": len(primes), "unsat": sum(g["result"] == "unsat" for g in generic),
           "max_time": max(g["time"] for g in generic), "total_time": sum(g["time"] for g in generic),
           "generic": generic, "in_pool": in_pool}
    write_json("prop_prime.json", out)
    print({k: v for k, v in out.items() if k != "generic"}, flush=True)


if __name__ == "__main__":
    main()
