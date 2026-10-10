"""Prove Propositions prop:max and prop:bound for every expression tree over up to four symbolic numbers"""

import itertools
import sys
import time

import z3

from common import solver, timed_check, write_json

GAME = list(range(1, 11)) + [25, 50, 75, 100]


def g(u, v):
    """Return max(uv, u + v) as a Z3 term"""
    return z3.If(u * v >= u + v, u * v, u + v)


def zmax(terms):
    """Return the maximum of a non-empty list of Z3 terms"""
    m = terms[0]
    for t in terms[1:]:
        m = z3.If(t > m, t, m)
    return m


def splits(S):
    """Yield each unordered split of the tuple S once with S's first element on the left"""
    rest = S[1:]
    for r in range(0, len(rest)):
        for left_rest in itertools.combinations(rest, r):
            L = (S[0],) + left_rest
            R = tuple(i for i in S if i not in L)
            yield L, R


def trees(S):
    """Yield every unordered binary tree whose leaves are exactly S"""
    if len(S) == 1:
        yield S[0]
        return
    for L, R in splits(S):
        for tl in trees(L):
            for tr in trees(R):
                yield (tl, tr)


def encode(tree, p, cs, ops=None, counter=None):
    """Return the value term of a tree and append the legality constraints of Definition def:ops to cs"""
    if counter is None:
        counter = [0]
    if isinstance(tree, int):
        return p[tree]
    a = encode(tree[0], p, cs, ops, counter)
    b = encode(tree[1], p, cs, ops, counter)
    k = counter[0]
    counter[0] += 1
    x = z3.If(a >= b, a, b)
    y = z3.If(a >= b, b, a)
    v = z3.Int(f"v{k}")
    choices = [
        z3.And(v == x + y),
        z3.And(x > y, v == x - y),
        z3.And(y != 1, v == x * y),
        z3.And(y != 1, x == y * v, v >= 1),
    ]
    # Fix the operator at this node when an operator assignment is given and leave it free otherwise
    cs.append(choices[ops[k]] if ops is not None else z3.Or(choices))
    return v


def B(S, p, memo):
    """Return the term B(S) of Proposition prop:max"""
    if S not in memo:
        if len(S) == 1:
            memo[S] = p[S[0]]
        else:
            memo[S] = zmax([g(B(L, p, memo), B(R, p, memo)) for L, R in splits(S)])
    return memo[S]


def check(n, S, tree, claim, regime, timeout, ops=None):
    """Return the result of refuting the claim for one tree over S within a pool of n numbers"""
    p = [z3.Int(f"p{i}") for i in range(n)]
    cs = []
    for v in p:
        cs.append(v >= 1)
        if regime == "game":
            cs.append(z3.Or([v == c for c in GAME]))
    val = encode(tree, p, cs, ops)
    if claim == "max":
        bad = val > B(tuple(range(n)), p, {})
    else:
        prod = 1
        for i in S:
            prod = prod * (p[i] + 1)
        bad = val + 1 > prod
    s = solver(timeout_ms=timeout)
    s.add(cs)
    s.add(bad)
    r, t = timed_check(s)
    return str(r), t


def generic_lemmas(timeout):
    """Prove the one-node facts from which both propositions follow by induction for any pool size"""
    x, y, a, b, A, Bv, r = z3.Ints("x y a b A B r")
    legal = z3.Or(r == x + y, z3.And(x > y, r == x - y), z3.And(y != 1, r == x * y), z3.And(y != 1, x == y * r, r >= 1))
    pos = z3.And(x >= y, y >= 1)
    goals = {
        "every legal result is at most max(xy, x+y)": z3.Implies(z3.And(pos, legal), r <= g(x, y)),
        "max(xy, x+y) is itself a legal result": z3.Implies(pos, z3.Or(
            z3.And(g(x, y) == x + y), z3.And(y != 1, g(x, y) == x * y))),
        "max(uv, u+v) is monotone in both arguments": z3.Implies(
            z3.And(a >= 1, b >= 1, a <= A, b <= Bv), g(a, b) <= g(A, Bv)),
        "max(xy, x+y) exceeds x so adding a number raises B": z3.Implies(pos, g(x, y) > x),
        "every legal result r has r + 1 <= (x+1)(y+1)": z3.Implies(z3.And(pos, legal), r + 1 <= (x + 1) * (y + 1)),
        "the product bound is monotone": z3.Implies(
            z3.And(a >= 1, b >= 1, a <= A, b <= Bv), (a + 1) * (b + 1) <= (A + 1) * (Bv + 1)),
    }
    out = []
    for name, goal in goals.items():
        s = solver(timeout_ms=timeout)
        s.add(z3.Not(goal))
        res, t = timed_check(s)
        out.append({"lemma": name, "result": str(res), "time": t})
        print("lemma", out[-1], flush=True)
    return out


def main():
    timeout = int(sys.argv[1]) * 1000 if len(sys.argv) > 1 else 120_000
    out = {"lemmas": generic_lemmas(timeout), "trees": []}
    write_json("prop_max_bound.json", out)
    for n in range(1, 5):
        for size in range(1, n + 1):
            for S in itertools.combinations(range(n), size):
                for tree in trees(S):
                    for claim in ("max", "bound"):
                        # Check the product bound only on whole pools since it is stated per subset
                        if claim == "bound" and size != n:
                            continue
                        for regime in ("game", "unbounded"):
                            # Skip game ranges at four leaves where the finite disjunctions time out and unbounded leaves imply them
                            if regime == "game" and n == 4:
                                continue
                            r, t = check(n, S, tree, claim, regime, 2 * timeout if regime == "game" else timeout)
                            row = {"n": n, "S": S, "tree": str(tree), "claim": claim, "regime": regime, "result": r, "time": t}
                            # Retry an open case with each operator assignment fixed which splits the disjunction
                            if r != "unsat" and regime == "unbounded":
                                nodes = len(S) - 1
                                sub = []
                                for ops in itertools.product(range(4), repeat=nodes):
                                    sub.append(check(n, S, tree, claim, regime, timeout, ops))
                                row["split_results"] = {k: sum(1 for x in sub if x[0] == k) for k in ("unsat", "sat", "unknown")}
                                row["split_time"] = sum(x[1] for x in sub)
                            out["trees"].append(row)
                            print(row, flush=True)
                            write_json("prop_max_bound.json", out)


if __name__ == "__main__":
    main()
