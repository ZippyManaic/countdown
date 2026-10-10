#!/usr/bin/env python3
"""Encode "some legal Countdown expression over the pool reaches a target in the set" as CNF or SMT-LIB, mirroring Enc in lean/CountdownSat/Enc.lean"""

import sys

NSTEPS = 5
NPOOL = 6
SELW = 4


def width_for(pool, target):
    """Return the least width w with prod(p_i + 1) <= 2^w and every target below 2^w"""
    target = target if isinstance(target, int) else max(target)
    prod = 1
    for v in pool:
        prod *= v + 1
    w = 1
    while (1 << w) < prod or (1 << w) <= target:
        w += 1
    return w


# Build back end 1 as an and-inverter graph with structural hashing, constant folding and Tseitin output

class AIG:
    """Store literals as 2 * node + sign so that node 0 is constant false and literals 0 and 1 are false and true"""

    def __init__(self):
        self.nnodes = 1
        self.inputs = set()
        self.ands = {}       # Map each node to its two input literals
        self.hash = {}

    def var(self):
        n = self.nnodes
        self.nnodes += 1
        self.inputs.add(n)
        return 2 * n

    @staticmethod
    def neg(a):
        return a ^ 1

    def and_(self, a, b):
        if a > b:
            a, b = b, a
        if a == 0:
            return 0
        if a == 1:
            return b
        if a == b:
            return a
        if a == b ^ 1:
            return 0
        key = (a, b)
        if key in self.hash:
            return self.hash[key]
        n = self.nnodes
        self.nnodes += 1
        self.ands[n] = key
        self.hash[key] = 2 * n
        return 2 * n

    def or_(self, a, b):
        return self.and_(a ^ 1, b ^ 1) ^ 1

    def xor(self, a, b):
        return self.or_(self.and_(a, b ^ 1), self.and_(a ^ 1, b))

    def mux(self, c, a, b):
        return self.or_(self.and_(c, a), self.and_(c ^ 1, b))

    def all_(self, lits):
        r = 1
        for x in lits:
            r = self.and_(r, x)
        return r

    def any_(self, lits):
        r = 0
        for x in lits:
            r = self.or_(r, x)
        return r


class BlastBuilder:
    """Build constraints as AIG literals over bit-vectors held as least-significant-first literal lists"""

    def __init__(self):
        self.g = AIG()
        self.asserted = []
        self.names = {}

    # Create variables and constants
    def bool_var(self, name):
        x = self.g.var()
        self.names[name] = [x]
        return x

    def bv_var(self, name, w):
        xs = [self.g.var() for _ in range(w)]
        self.names[name] = xs
        return xs

    def const(self, n, w):
        assert 0 <= n < (1 << w)
        return [1 if (n >> i) & 1 else 0 for i in range(w)]

    TRUE = 1
    FALSE = 0

    # Combine Boolean literals
    def not_(self, a):
        return a ^ 1

    def and_(self, *xs):
        return self.g.all_(xs)

    def or_(self, *xs):
        return self.g.any_(xs)

    def implies(self, a, b):
        return self.g.or_(a ^ 1, b)

    # Compare and combine bit-vectors
    def eq(self, a, b):
        assert len(a) == len(b)
        return self.g.all_([self.g.xor(x, y) ^ 1 for x, y in zip(a, b)])

    def ult(self, a, b):
        assert len(a) == len(b)
        lt = 0
        for x, y in zip(a, b):
            # Scan from the least significant bit so the most significant difference decides
            lt = self.g.or_(self.g.and_(x ^ 1, y), self.g.and_(self.g.xor(x, y) ^ 1, lt))
        return lt

    def zext(self, a, w):
        return list(a) + [0] * (w - len(a))

    def add(self, a, b):
        assert len(a) == len(b)
        out, c = [], 0
        for x, y in zip(a, b):
            s = self.g.xor(self.g.xor(x, y), c)
            c = self.g.or_(self.g.and_(x, y), self.g.and_(c, self.g.xor(x, y)))
            out.append(s)
        return out

    def mul(self, a, b):
        assert len(a) == len(b)
        w = len(a)
        acc = [0] * w
        for i, y in enumerate(b):
            pp = [0] * i + [self.g.and_(x, y) for x in a[: w - i]]
            acc = self.add(acc, pp)
        return acc

    def mux(self, c, a, b):
        return [self.g.mux(c, x, y) for x, y in zip(a, b)]

    def assert_(self, lit):
        self.asserted.append(lit)

    # Write DIMACS
    def dimacs(self):
        g = self.g
        # Keep only nodes reachable from the asserted literals
        need, stack = set(), [l >> 1 for l in self.asserted]
        while stack:
            n = stack.pop()
            if n in need or n == 0:
                continue
            need.add(n)
            if n in g.ands:
                a, b = g.ands[n]
                stack.append(a >> 1)
                stack.append(b >> 1)
        # Number every input variable even when unused so models always decode
        order = sorted(need | g.inputs)
        num = {n: i + 1 for i, n in enumerate(order)}

        def lit(l):
            if l >> 1 == 0:
                return None
            v = num[l >> 1]
            return -v if l & 1 else v

        clauses = []
        for n in order:
            if n in g.ands and n in need:
                a, b = g.ands[n]
                x, la, lb = num[n], lit(a), lit(b)
                clauses.append([-x, la])
                clauses.append([-x, lb])
                clauses.append([x, -la, -lb])
        for l in self.asserted:
            if l == 1:
                continue
            if l == 0:
                clauses.append([])
                continue
            clauses.append([lit(l)])
        varmap = {name: [None if l >> 1 == 0 else num[l >> 1] for l in bits]
                  for name, bits in self.names.items()}
        lines = [f"p cnf {len(order)} {len(clauses)}"]
        lines += [" ".join(map(str, c)) + " 0" for c in clauses]
        return "\n".join(lines) + "\n", varmap


# Build back end 2 as SMT-LIB text so that Z3's own bit-blaster can cross-check ours

class SmtBuilder:
    def __init__(self):
        self.decls = []
        self.asserted = []

    TRUE = "true"
    FALSE = "false"

    def bool_var(self, name):
        self.decls.append(f"(declare-const {name} Bool)")
        return name

    def bv_var(self, name, w):
        self.decls.append(f"(declare-const {name} (_ BitVec {w}))")
        return (name, w)

    def const(self, n, w):
        return (f"(_ bv{n} {w})", w)

    def not_(self, a):
        return f"(not {a})"

    def and_(self, *xs):
        return "(and " + " ".join(xs) + ")" if xs else "true"

    def or_(self, *xs):
        return "(or " + " ".join(xs) + ")" if xs else "false"

    def implies(self, a, b):
        return f"(=> {a} {b})"

    def eq(self, a, b):
        assert a[1] == b[1]
        return f"(= {a[0]} {b[0]})"

    def ult(self, a, b):
        return f"(bvult {a[0]} {b[0]})"

    def zext(self, a, w):
        return (f"((_ zero_extend {w - a[1]}) {a[0]})", w) if w > a[1] else a

    def add(self, a, b):
        return (f"(bvadd {a[0]} {b[0]})", a[1])

    def mul(self, a, b):
        return (f"(bvmul {a[0]} {b[0]})", a[1])

    def mux(self, c, a, b):
        return (f"(ite {c} {a[0]} {b[0]})", a[1])

    def assert_(self, x):
        self.asserted.append(x)

    def text(self):
        return "\n".join(["(set-logic QF_BV)"] + self.decls +
                         [f"(assert {a})" for a in self.asserted] + ["(check-sat)", "(get-model)"]) + "\n"


# Write the encoding once against the builder interface

def intervals(targets):
    """Merge a set of targets into sorted disjoint closed intervals"""
    ivs = []
    for t in sorted(set(targets)):
        if ivs and ivs[-1][1] + 1 == t:
            ivs[-1][1] = t
        else:
            ivs.append([t, t])
    return [tuple(iv) for iv in ivs]


def in_set(B, x, ivs, w):
    return B.or_(*[B.and_(B.not_(B.ult(x, B.const(lo, w))), B.not_(B.ult(B.const(hi, w), x))) for lo, hi in ivs])


def build(B, pool, target, w, prune=True):
    targets = [target] if isinstance(target, int) else list(target)
    ivs = intervals(targets)
    assert len(pool) == NPOOL
    act = [B.bool_var(f"act{k}") for k in range(NSTEPS)]
    sa = [B.bv_var(f"sa{k}", SELW) for k in range(NSTEPS)]
    sb = [B.bv_var(f"sb{k}", SELW) for k in range(NSTEPS)]
    o1 = [B.bool_var(f"opm{k}") for k in range(NSTEPS)]   # Choose the multiplicative pair when set
    o0 = [B.bool_var(f"opi{k}") for k in range(NSTEPS)]   # Choose the inverse operation when set
    xa = [B.bv_var(f"xa{k}", w) for k in range(NSTEPS)]
    xb = [B.bv_var(f"xb{k}", w) for k in range(NSTEPS)]
    r = [B.bv_var(f"r{k}", w) for k in range(NSTEPS)]
    reg = [B.const(v, w) for v in pool] + r
    sel = lambda j: B.const(j, SELW)
    zero = B.const(0, w)

    for k in range(NSTEPS):
        cs = []
        if k > 0:
            B.assert_(B.implies(act[k], act[k - 1]))                     # Keep the active steps a prefix (C1)
        cs.append(B.ult(sa[k], sel(NPOOL + k)))                          # Read operands only from earlier registers (C2)
        cs.append(B.ult(sb[k], sel(NPOOL + k)))
        for j in range(NPOOL + k):                                        # Tie each operand value to the register it selects (C3)
            cs.append(B.implies(B.eq(sa[k], sel(j)), B.eq(xa[k], reg[j])))
            cs.append(B.implies(B.eq(sb[k], sel(j)), B.eq(xb[k], reg[j])))
        cs.append(B.not_(B.eq(r[k], zero)))                               # Keep every result positive (C4)
        # Share one adder and one multiplier by letting the inverse operation swap the roles of xa and r
        lo = B.mux(o0[k], r[k], xa[k])
        hi = B.mux(o0[k], xa[k], r[k])
        add_ok = B.eq(B.add(B.zext(xb[k], w + 1), B.zext(lo, w + 1)), B.zext(hi, w + 1))
        mul_ok = B.eq(B.mul(B.zext(xb[k], 2 * w), B.zext(lo, 2 * w)), B.zext(hi, 2 * w))
        cs.append(B.implies(B.not_(o1[k]), add_ok))
        cs.append(B.implies(o1[k], mul_ok))
        cs.append(B.implies(B.not_(o0[k]), B.ult(sa[k], sb[k])))
        if prune:                                                         # Forbid a result equal to an operand or an early target value (C10)
            cs.append(B.not_(B.eq(r[k], xa[k])))
            cs.append(B.not_(B.eq(r[k], xb[k])))
            if k + 1 < NSTEPS:
                cs.append(B.implies(act[k + 1], B.not_(in_set(B, r[k], ivs, w))))
        if prune:
            if k > 0:                                                     # Force the previous step to be an operand whenever a step result is (C8)
                internal = B.or_(B.not_(B.ult(sa[k], sel(NPOOL))), B.not_(B.ult(sb[k], sel(NPOOL))))
                prev = B.or_(B.eq(sa[k], sel(NPOOL + k - 1)), B.eq(sb[k], sel(NPOOL + k - 1)))
                cs.append(B.implies(internal, prev))
        B.assert_(B.implies(act[k], B.and_(*cs)))

    slots = [(k, s) for k in range(NSTEPS) for s in (sa, sb)]           # Use each register at most once (C5)
    for i in range(len(slots)):
        for j in range(i + 1, len(slots)):
            (k, s), (k2, s2) = slots[i], slots[j]
            B.assert_(B.implies(act[k2], B.not_(B.eq(s[k], s2[k2]))))

    if prune:                                                             # Feed every result but the last to a later step (C7)
        for k in range(NSTEPS - 1):
            uses = [B.and_(act[k2], B.eq(s[k2], sel(NPOOL + k)))
                    for k2 in range(k + 1, NSTEPS) for s in (sa, sb)]
            B.assert_(B.implies(act[k + 1], B.or_(*uses)))

    leaf_hit = any(v in targets for v in pool)                                             # Put the last result in the target set (C6)
    last = []
    for k in range(NSTEPS):
        is_last = B.and_(act[k], B.not_(act[k + 1])) if k + 1 < NSTEPS else act[k]
        last.append(B.implies(is_last, in_set(B, r[k], ivs, w)))
    B.assert_(B.TRUE if leaf_hit else B.and_(act[0], *last))


# Decode models and evaluate expressions independently of the encoding

def decode(model, varmap, pool, target):
    """Turn a CaDiCaL model into an infix expression string or None when the target is a pool number"""
    val = lambda name: sum(1 << i for i, v in enumerate(varmap[name]) if v is not None and model.get(v, False))
    exprs = [str(v) for v in pool]
    out = None
    for k in range(NSTEPS):
        if not val(f"act{k}"):
            break
        a, b = val(f"sa{k}"), val(f"sb{k}")
        op = "+-*/"[2 * val(f"opm{k}") + val(f"opi{k}")]
        exprs.append(f"({exprs[a]} {op} {exprs[b]})")
        out = exprs[-1]
    return out


def evaluate(expr, pool):
    """Evaluate an infix expression under the game's rules and check its use of the pool, raising on any breach"""
    toks = expr.replace("(", " ( ").replace(")", " ) ").split()
    pos = 0
    used = []

    def parse():
        nonlocal pos
        t = toks[pos]
        pos += 1
        if t == "(":
            a = parse()
            op = toks[pos]
            pos += 1
            b = parse()
            assert toks[pos] == ")"
            pos += 1
            if op == "+":
                v = a + b
            elif op == "-":
                assert b < a, "non-positive difference"
                v = a - b
            elif op == "*":
                v = a * b
            elif op == "/":
                assert b > 0 and a % b == 0, "inexact division"
                v = a // b
            else:
                raise AssertionError(op)
            assert v > 0
            return v
        v = int(t)
        assert v > 0
        used.append(v)
        return v

    v = parse()
    assert pos == len(toks)
    rest = list(pool)
    for u in used:
        rest.remove(u)  # Raise ValueError when a number is used more often than the pool holds
    return v


def cnf_for(pool, target, w=None, prune=True):
    w = w or width_for(pool, target)
    B = BlastBuilder()
    build(B, pool, target, w, prune)
    return B.dimacs()


def smt_for(pool, target, w=None, prune=True):
    w = w or width_for(pool, target)
    B = SmtBuilder()
    build(B, pool, target, w, prune)
    return B.text()


if __name__ == "__main__":
    pool = [int(x) for x in sys.argv[1].split(",")]
    target = int(sys.argv[2])
    if len(sys.argv) > 3 and sys.argv[3] == "smt":
        sys.stdout.write(smt_for(pool, target))
    else:
        sys.stdout.write(cnf_for(pool, target)[0])
