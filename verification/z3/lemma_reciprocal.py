"""Check Lemma lem:reciprocal against the exact division test in countdown-c/solver.c"""

# The C code computes q = (uint32_t)_mm_cvtsd_si32((double)x * (1.0 / y)) and accepts when q * y == x in uint32
# arithmetic, with the default MXCSR mode so every rounding is to nearest with ties to even

import random
import sys
import time

import z3

from common import solver, timed_check, write_json

RNE = z3.RNE()
D = z3.Float64()
INT_MIN = -(2**31)


# Part A: the C expression in Z3's IEEE floating-point theory over 32-bit vectors

def fp_quotient(x, y):
    """Return the 32-bit result of the C quotient() for 32-bit vectors x and y"""
    inv = z3.fpDiv(RNE, z3.FPVal(1.0, D), z3.fpToFPUnsigned(RNE, y, D))
    prod = z3.fpMul(RNE, z3.fpToFPUnsigned(RNE, x, D), inv)
    # Model cvtsd2si which returns the integer indefinite value 0x80000000 when the rounded result is out of range
    big = z3.fpGEQ(prod, z3.FPVal(2.0**31 - 0.5, D))
    return z3.If(big, z3.BitVecVal(2**31, 32), z3.fpToSBV(RNE, prod, z3.BitVecSort(32)))


def fp_soundness(jlo, jhi, xmax, timeout):
    """Show the C test never accepts unless q * y equals x exactly in 64 bits for y in [2^jlo, 2^jhi)"""
    x, y = z3.BitVecs("x y", 32)
    q = fp_quotient(x, y)
    s = solver("QF_FPBV", timeout)
    lo = max(2**jlo, 1)
    s.add(z3.UGE(y, lo), z3.ULT(z3.ZeroExt(32, y), 2**jhi), z3.ULE(y, x), z3.ULE(z3.ZeroExt(32, x), xmax - 1))
    s.add(q * y == x, z3.ZeroExt(32, q) * z3.ZeroExt(32, y) != z3.ZeroExt(32, x))
    return timed_check(s)


def fp_completeness(bits, timeout):
    """Show y | x implies the C test accepts with q = x / y for all 1 <= y <= x < 2^bits"""
    x, y, k = z3.BitVecs("x y k", 32)
    q = fp_quotient(x, y)
    s = solver("QF_FPBV", timeout)
    s.add(z3.UGE(y, 1), z3.UGE(k, 1), z3.ULT(k, 2**bits), z3.ULT(y, 2**bits))
    s.add(z3.ZeroExt(32, k) * z3.ZeroExt(32, y) == z3.ZeroExt(32, x), z3.ULT(x, 2**bits))
    s.add(q != k)
    return timed_check(s)


# Part B: the same C expression with IEEE round-to-nearest-even written out exactly in integer arithmetic

def rne(n, num, den):
    """Constrain integer n to be num / den rounded to nearest with ties to even for den > 0"""
    d = 2 * (n * den - num)
    return z3.Or(z3.And(d < den, d > -den), z3.And(z3.Or(d == den, d == -den), n % 2 == 0))


def int_quotient(x, xa, y, j, fs, P=53, trunc=False):
    """Return q, its constraints, the binade coverage term and the product numerator for x in binade xa and y in binade j"""
    # Write 1/y as m1 / 2^(j+P) for a P-bit significand and round the product to m2 2^f in whichever binade f the coverage term allows
    m1, m2, q = z3.Int("m1"), z3.Int("m2"), z3.Int("q")
    cs = [rne(m1, 2 ** (j + P), y)]
    prod_num = x * m1
    cases, cover = [], []
    for f in fs:
        E = j + P + f
        # Express the product as prod_num / 2^E in units of 2^f so the significand lies in [2^(P-1), 2^P)
        if E >= 0:
            inside = z3.And(prod_num >= 2 ** (P - 1) * 2**E, prod_num < 2**P * 2**E)
            sig = rne(m2, prod_num, 2**E)
        else:
            inside = z3.And(prod_num * 2 ** (-E) >= 2 ** (P - 1), prod_num * 2 ** (-E) < 2**P)
            sig = m2 == prod_num * 2 ** (-E)
        if f >= 0:
            to_int = q == m2 * 2**f
        elif trunc:
            # Truncate toward zero as a plain C cast would for the mutation test
            to_int = z3.And(q * 2 ** (-f) <= m2, m2 < (q + 1) * 2 ** (-f))
        else:
            to_int = rne(q, m2, 2 ** (-f))
        cover.append(inside)
        cases.append(z3.And(inside, sig, to_int))
    cs.append(z3.Or(cases))
    return q, cs, z3.Or(cover), prod_num


def c_test(q, width=32):
    """Return the unsigned quotient after cvtsd2si saturates to the integer indefinite value and the unsigned cast"""
    qc = z3.If(q < 2 ** (width - 1), q, -(2 ** (width - 1)))
    return z3.If(qc >= 0, qc, qc + 2**width)


def int_case(kind, a, j, xmax, ymin, timeout, P=53, width=32, xmin=0, trunc=False):
    """Run one binade pair: a is the binade of k for completeness or of x for soundness and j that of y"""
    y = z3.Int("y")
    s = solver("QF_NIA", timeout)
    s.add(y >= max(2**j, ymin), y < 2 ** (j + 1))
    if kind == "complete":
        k = z3.Int("k")
        x = k * y
        s.add(k >= 2**a, k < 2 ** (a + 1), x < xmax, x >= xmin)
        # The quotient x / y = k lies in binade a so the product lies within one binade of it
        fs = [a + d - (P - 1) for d in (-2, -1, 0, 1)]
    else:
        x = z3.Int("x")
        s.add(x >= 2**a, x < 2 ** (a + 1), x < xmax, x >= y, x >= xmin)
        fs = [a - j + d - (P - 1) for d in (-3, -2, -1, 0, 1)]
    q, cs, cover, prod_num = int_quotient(x, a, y, j, fs, P, trunc)
    s.add(cs)
    # Ask separately whether the product can miss every binade tried which would make the main query vacuous
    c = solver("QF_NIA", timeout)
    c.add(y >= max(2**j, ymin), y < 2 ** (j + 1), rne(z3.Int("m1"), 2 ** (j + P), y))
    if kind == "complete":
        c.add(k >= 2**a, k < 2 ** (a + 1), x < xmax)
    else:
        c.add(x >= 2**a, x < 2 ** (a + 1), x < xmax, x >= y)
    c.add(z3.Not(cover))
    rc, tc = timed_check(c)
    qu = c_test(q, width)
    if kind == "complete":
        # Accepting follows from qu = k since then qu * y = x exactly
        s.add(qu != k)
    else:
        # Accepting means qu * y = x + w 2^32 for some w and only w = 0 gives y | x with qu = x / y
        w = z3.Int("w")
        s.add(qu * y == x + w * 2**width, w != 0)
    r, t = timed_check(s)
    model = None
    if r == z3.sat:
        m = s.model()
        model = {d.name(): m[d].as_long() for d in m.decls() if d.name() in ("k", "x", "y", "q")}
    return str(r), t, str(rc), tc, model


def py_quotient(x, y):
    """Return the C quotient computed with Python floats which are IEEE doubles rounded to nearest even"""
    p = float(x) * (1.0 / float(y))
    r = round(p)
    return r if r < 2**31 else 2**31


def int_model_eval(x, y):
    """Evaluate the integer model at concrete x and y and confirm it determines q uniquely"""
    a, j = x.bit_length() - 1, y.bit_length() - 1
    fs = [a - j + d - 52 for d in (-3, -2, -1, 0, 1)]
    q, cs, cover, _ = int_quotient(z3.IntVal(x), a, z3.IntVal(y), j, fs)
    cs = cs + [cover]
    s = z3.Solver()
    s.add(cs)
    assert s.check() == z3.sat
    v = s.model()[q].as_long()
    s.add(q != v)
    assert s.check() == z3.unsat
    return v if v < 2**31 else 2**31


def fp_eval(x, y):
    """Evaluate the floating-point encoding at concrete x and y"""
    q = fp_quotient(z3.BitVecVal(x, 32), z3.BitVecVal(y, 32))
    v = z3.simplify(q).as_long()
    return v


def part_validate():
    """Compare both encodings with Python's IEEE doubles on edge and random inputs"""
    rng = random.Random(1)
    edges = (1, 2, 3, 2**31 - 1, 2**31 - 2, 2**32 - 1, 2**30 + 3)
    samples = [(x, y) for x in edges for y in (1, 2, 3, 7, 49, 2**15 + 1, x) if y <= x]
    for _ in range(600):
        x = rng.randrange(1, 2**32)
        samples.append((x, rng.randrange(1, x + 1)))
    for _ in range(300):
        k, y = rng.randrange(1, 2**16), rng.randrange(2, 2**16)
        samples.append((k * y, y))
    bad = []
    for x, y in samples:
        p = py_quotient(x, y)
        i = int_model_eval(x, y)
        f = fp_eval(x, y)
        if not p == i == f:
            bad.append((x, y, p, i, f))
    # Record the y = 1 edge where cvtsd2si saturates just above 2^31
    edge = [{"x": x, "q": int_model_eval(x, 1), "accepted": int_model_eval(x, 1) == x} for x in (2**31 - 1, 2**31, 2**31 + 1)]
    return {"samples": len(samples), "disagreements": bad, "y_equals_1_edge": edge}


def part_int32(timeout):
    """Prove the 32-bit C test exact for 2 <= y <= x < 2^32 and for y = 1 with x < 2^31 by binade pairs"""
    rows = []
    for kind in ("complete", "sound"):
        for j in range(0, 32):
            ymin, xmax = (1, 2**31) if j == 0 else (2, 2**32)
            for a in range(0, 32):
                if (kind == "sound" and a < j) or (kind == "complete" and a + j > 31):
                    continue
                r, t, rc, tc, model = int_case(kind, a, j, xmax, ymin, timeout)
                rows.append({"kind": kind, "a": a, "j": j, "xmax": xmax, "result": r, "time": t,
                             "coverage": rc, "coverage_time": tc, "model": model})
                if r != "unsat" or rc != "unsat":
                    print("ATTENTION", rows[-1], flush=True)
            write_json("lemma_reciprocal_int32_partial.json", {"summary": summarise(rows), "rows": rows})
    return {"summary": summarise(rows), "rows": rows}


def part_wide(timeout, blo, bhi):
    """Prove completeness of the test widened to uint64 and cvtsd2si64 for x in binades blo to bhi - 1"""
    rows = []
    for b in range(blo, bhi):
        for a in range(0, b + 1):
            for j in range(1, b + 1):
                if a + j in (b - 1, b):
                    r, t, rc, tc, model = int_case("complete", a, j, 2 ** (b + 1), 2, timeout, 53, 64, 2**b)
                    rows.append({"kind": "complete", "b": b, "a": a, "j": j, "result": r, "time": t,
                                 "coverage": rc, "coverage_time": tc, "model": model})
                    if r != "unsat" or rc != "unsat":
                        print("ATTENTION", rows[-1], flush=True)
        print("wide binade", b, "done", flush=True)
        write_json(f"lemma_reciprocal_wide_{blo}_{bhi}.json", {"summary": summarise(rows), "rows": rows})
    return {"summary": summarise(rows), "rows": rows}


def part_mutation(timeout):
    """Show the integer model finds failures when the final rounding is a truncating C cast"""
    r, t, rc, tc, model = int_case("complete", 20, 9, 2**32, 2, timeout, trunc=True)
    out = {"result": r, "time": t, "witness": model}
    if model:
        k, y = model["k"], model["y"]
        q = int(float(k * y) * (1.0 / y))
        out.update({"python_truncated_q": q, "confirmed": q != k})
    return out


def part_fp(budget_s):
    """Run the floating-point theory checks of soundness by divisor binade and completeness by growing width"""
    sound = []
    for j in range(1, 32):
        r, t = fp_soundness(j, j + 1, 2**32, budget_s * 1000)
        sound.append({"j": j, "result": str(r), "time": t})
        print("fp soundness", sound[-1], flush=True)
    comp = []
    for bits in range(4, 33, 2):
        r, t = fp_completeness(bits, budget_s * 1000)
        comp.append({"bits": bits, "result": str(r), "time": t})
        print("fp completeness", comp[-1], flush=True)
        if r != z3.unsat:
            break
    return {"soundness": sound, "completeness": comp}


def summarise(rows):
    """Count results and time per kind"""
    summary = {}
    for row in rows:
        s = summary.setdefault(row["kind"], {"cases": 0, "unsat": 0, "coverage_unsat": 0, "time": 0.0, "max_time": 0.0})
        s["cases"] += 1
        s["unsat"] += row["result"] == "unsat"
        s["coverage_unsat"] += row["coverage"] == "unsat"
        s["time"] += row["time"] + row["coverage_time"]
        s["max_time"] = max(s["max_time"], row["time"])
    return summary


def main():
    part = sys.argv[1]
    t0 = time.time()
    if part == "validate":
        out = part_validate()
    elif part == "int32":
        out = part_int32(int(sys.argv[2]) * 1000 if len(sys.argv) > 2 else 600_000)
    elif part == "wide":
        out = part_wide(600_000, int(sys.argv[2]), int(sys.argv[3]))
    elif part == "mutation":
        out = part_mutation(300_000)
    elif part == "fp":
        out = part_fp(int(sys.argv[2]) if len(sys.argv) > 2 else 600)
    else:
        raise SystemExit("usage: lemma_reciprocal.py validate|int32|wide BLO BHI|mutation|fp [SECONDS]")
    out["wall_time"] = time.time() - t0
    name = f"lemma_reciprocal_{part}" + (f"_{sys.argv[2]}_{sys.argv[3]}" if part == "wide" else "") + ".json"
    if part == "fp" or part == "int32":
        name = f"lemma_reciprocal_{part}.json"
    write_json(name, out)
    print(part, "summary", {k: v for k, v in out.items() if k not in ("rows",)} if part != "int32" else out["summary"], flush=True)


if __name__ == "__main__":
    main()
