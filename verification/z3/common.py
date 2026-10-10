"""Share helpers between the Z3 cross-checks of the Countdown paper"""

import json
import os
import time

import z3

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
OUT = os.path.join(HERE, "results")

# Cap Z3's own heap in megabytes on top of the systemd scope that run_all.sh applies
z3.set_param("memory_max_size", 3000)


def solver(logic=None, timeout_ms=300_000):
    """Return a solver with a per-query timeout"""
    s = z3.SolverFor(logic) if logic else z3.Solver()
    s.set("timeout", timeout_ms)
    return s


def timed_check(s):
    """Return the check result and its wall time in seconds"""
    t = time.time()
    r = s.check()
    return r, time.time() - t


def write_json(name, data):
    """Write a result file under results/"""
    os.makedirs(OUT, exist_ok=True)
    with open(os.path.join(OUT, name), "w") as f:
        json.dump(data, f, indent=1)


def legal_ops(x, y):
    """Return the legal (result, operator) pairs of Definition def:ops for x >= y >= 1"""
    out = [(x + y, "+")]
    if x > y:
        out.append((x - y, "-"))
    if y != 1:
        out.append((x * y, "*"))
        if x % y == 0:
            out.append((x // y, "/"))
    return out


def reachable(pool):
    """Return every value reachable from the pool by Theorem thm:recursion computed independently of Z3"""
    n = len(pool)
    V = {1 << i: {pool[i]} for i in range(n)}
    for mask in range(1, 1 << n):
        if mask in V:
            continue
        vals = set()
        sub = (mask - 1) & mask
        while sub:
            rest = mask ^ sub
            if sub < rest:
                for a in V[sub]:
                    for b in V[rest]:
                        for r, _ in legal_ops(max(a, b), min(a, b)):
                            vals.add(r)
            sub = (sub - 1) & mask
        V[mask] = vals
    out = set()
    for v in V.values():
        out |= v
    return out


def read_misses(name):
    """Return a dict from sorted pool tuple to the set of missed targets"""
    path = os.path.join(ROOT, "solvability", "data", name)
    res = {}
    with open(path) as f:
        next(f)
        for line in f:
            pool, count, targets = line.rstrip("\n").split("\t")
            key = tuple(sorted(int(v) for v in pool.split()))
            ts = {int(t) for t in targets.split(",")} if targets else set()
            assert len(ts) == int(count)
            res[key] = ts
    return res


# Encode "some legal expression over the pool reaches a value" as a straight-line program
OPS = ("+", "-", "*", "/")


class Program:
    """Encode a straight-line program over a pool in unbounded integers where each node feeds at most one step"""

    # Number leaves 0 to n - 1 and step k's result n + k so single consumption makes the steps a forest

    def __init__(self, pool, steps=None, name="p"):
        self.pool = list(pool)
        n = self.n = len(pool)
        self.steps = n - 1 if steps is None else steps
        self.cs = []
        self.val = [z3.IntVal(v) for v in pool]
        self.active, self.lsel, self.rsel, self.op = [], [], [], []
        for k in range(self.steps):
            m = n + k
            act = z3.Bool(f"{name}_act{k}")
            # Pick the larger operand l and smaller operand r from earlier nodes as one-hot selectors
            ls = [z3.Bool(f"{name}_l{k}_{j}") for j in range(m)]
            rs = [z3.Bool(f"{name}_r{k}_{j}") for j in range(m)]
            op = z3.Int(f"{name}_op{k}")
            x = z3.Int(f"{name}_x{k}")
            y = z3.Int(f"{name}_y{k}")
            v = z3.Int(f"{name}_v{k}")
            cs = self.cs
            if k > 0:
                cs.append(z3.Implies(act, self.active[k - 1]))
            cs.append(z3.Implies(act, z3.PbEq([(b, 1) for b in ls], 1)))
            cs.append(z3.Implies(act, z3.PbEq([(b, 1) for b in rs], 1)))
            cs.append(z3.Implies(z3.Not(act), z3.And([z3.Not(b) for b in ls + rs])))
            for j in range(m):
                cs.append(z3.Not(z3.And(ls[j], rs[j])))
                cs.append(z3.Implies(ls[j], x == self.val[j]))
                cs.append(z3.Implies(rs[j], y == self.val[j]))
            cs.append(z3.Implies(act, z3.And(x >= y, y >= 1, v >= 1)))
            cs.append(z3.Implies(z3.Not(act), v == 0))
            cs.append(z3.And(op >= 0, op <= 3))
            # Allow + always, - when x > y, * when y != 1 and / when y != 1 and x = y v
            cs.append(z3.Implies(act, z3.Or(
                z3.And(op == 0, v == x + y),
                z3.And(op == 1, x > y, v == x - y),
                z3.And(op == 2, y != 1, v == x * y),
                z3.And(op == 3, y != 1, x == y * v))))
            self.active.append(act)
            self.lsel.append(ls)
            self.rsel.append(rs)
            self.op.append(op)
            self.val.append(v)
        # Consume each node at most once across all steps
        total = n + self.steps
        for j in range(total):
            uses = []
            for k in range(self.steps):
                if j < n + k:
                    uses += [(self.lsel[k][j], 1), (self.rsel[k][j], 1)]
            if uses:
                self.cs.append(z3.PbLe(uses, 1))

    def reaches(self, t):
        """Return a constraint that some node has value t"""
        return z3.Or([v == t for v in self.val])

    def decode(self, model, t):
        """Rebuild the steps and expression strings from a model"""
        exprs = [str(v) for v in self.pool]
        vals = list(self.pool)
        steps = []
        for k in range(self.steps):
            if not z3.is_true(model.eval(self.active[k], model_completion=True)):
                break
            l = [j for j, b in enumerate(self.lsel[k]) if z3.is_true(model.eval(b, model_completion=True))][0]
            r = [j for j, b in enumerate(self.rsel[k]) if z3.is_true(model.eval(b, model_completion=True))][0]
            o = OPS[model.eval(self.op[k], model_completion=True).as_long()]
            steps.append((l, r, o))
            exprs.append(f"({exprs[l]} {o} {exprs[r]})")
            vals.append(None)
        return steps, exprs

    def check_witness(self, steps, t):
        """Evaluate decoded steps independently of Z3 and return the node index holding t or None"""
        vals = list(self.pool)
        used = set()
        for l, r, o in steps:
            if l in used or r in used or l == r:
                return None
            used |= {l, r}
            x, y = vals[l], vals[r]
            if x < y:
                return None
            got = dict((op, res) for res, op in legal_ops(x, y))
            if o not in got:
                return None
            vals.append(got[o])
        for i, v in enumerate(vals):
            if v == t:
                return i
        return None
