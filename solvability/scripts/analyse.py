"""
Compute exact solvability statistics from the checker's results and write the data files RESULTS.md quotes
"""

import os
from collections import Counter, defaultdict
from fractions import Fraction
from math import prod

from common import DATA, LARGE, TARGETS, deal_probability, load_checker, load_pools


def is_prime(n):
    return n > 1 and all(n % d for d in range(2, int(n ** 0.5) + 1))


def largest_prime_factor(n):
    best, d = 1, 2
    while n > 1:
        while n % d == 0:
            best, n = d, n // d
        d += 1
    return best


def product_sum_bound(pool):
    """
    Return the largest value of the recursion max(a*b, a+b) over subset splits, which needs only + and *
    """
    best = [0] * (1 << len(pool))
    for mask in range(1, 1 << len(pool)):
        if mask & (mask - 1) == 0:
            best[mask] = pool[mask.bit_length() - 1]
            continue
        left = (mask - 1) & mask
        while left:
            a, b = best[left], best[mask ^ left]
            best[mask] = max(best[mask], a * b, a + b)
            left = (left - 1) & mask
    return best[-1]


def dec(x, places=6):
    return f"{float(x):.{places}f}"


def frac(x):
    return f"{x.numerator}/{x.denominator}"


def main():
    checker = load_checker()
    pools = load_pools()
    P = {p: deal_probability(p) for p in pools}
    assert sum(P.values()) == 1, "deal probabilities do not sum to one"
    ell = {p: sum(x in LARGE for x in p) for p in pools}
    P_ell = {1: Fraction(1, 2), 2: Fraction(1, 2)}
    for e in (1, 2):
        assert sum(P[p] for p in pools if ell[p] == e) == P_ell[e]
    miss = {p: checker[p][2] for p in pools}
    out = []
    say = out.append

    # Write the cross-check file for the formal proof in the table's pool order
    with open(os.path.join(DATA, "misses.tsv"), "w") as f:
        f.write("pool\tmiss_count\tmissed_targets\n")
        for p in pools:
            f.write(f"{' '.join(map(str, p))}\t{len(miss[p])}\t{','.join(map(str, sorted(miss[p])))}\n")

    say("== Headline ==")
    p_miss = sum(P[p] * len(miss[p]) for p in pools) / 900
    say(f"P(no exact) = {frac(p_miss)} = {dec(p_miss, 12)}")
    by_ell = {}
    for e in (1, 2):
        by_ell[e] = sum(P[p] * len(miss[p]) for p in pools if ell[p] == e) / 900 / P_ell[e]
        say(f"P(no exact | {e} large) = {frac(by_ell[e])} = {dec(by_ell[e], 12)}")
    assert p_miss == (by_ell[1] + by_ell[2]) / 2
    total = sum(len(miss[p]) for p in pools)
    uni = Fraction(total, len(pools) * 900)
    say(f"uniform over instances: {total:,} of {len(pools) * 900:,} = {frac(uni)} = {dec(uni, 12)}")
    for e in (1, 2):
        n_e = sum(1 for p in pools if ell[p] == e)
        m_e = sum(len(miss[p]) for p in pools if ell[p] == e)
        say(f"  {e} large: {m_e:,} of {n_e * 900:,} instances = {dec(Fraction(m_e, n_e * 900), 6)} over {n_e} pools")

    say("\n== Miss counts per pool ==")
    counts = {p: len(miss[p]) for p in pools}
    buckets = [(0, 0), (1, 1), (2, 5), (6, 10), (11, 20), (21, 50), (51, 100), (101, 200), (201, 400), (401, 900)]
    say("misses\tpools(1L)\tpools(2L)\tpools\tP(deal such a pool)")
    for lo, hi in buckets:
        sel = [p for p in pools if lo <= counts[p] <= hi]
        mass = sum(P[p] for p in sel)
        say(f"{lo}-{hi}\t{sum(ell[p] == 1 for p in sel)}\t{sum(ell[p] == 2 for p in sel)}\t{len(sel)}\t{dec(mass)}")
    perfect = [p for p in pools if counts[p] == 0]
    mass = sum(P[p] for p in perfect)
    say(f"pools reaching every target: {len(perfect)} ({sum(ell[p] == 1 for p in perfect)} one-large, "
        f"{sum(ell[p] == 2 for p in perfect)} two-large), deal probability {frac(mass)} = {dec(mass, 9)}")
    for e in (1, 2):
        m = sum(P[p] for p in perfect if ell[p] == e) / P_ell[e]
        say(f"  P(pool reaches everything | {e} large) = {dec(m, 9)}")
    for large in [(25,), (50,), (75,), (100,), (25, 50), (25, 75), (25, 100), (50, 75), (50, 100), (75, 100)]:
        sel = [p for p in pools if tuple(x for x in p if x in LARGE) == large]
        good = sum(counts[p] == 0 for p in sel)
        rate = sum(P[p] * counts[p] for p in sel) / 900 / sum(P[p] for p in sel)
        say(f"  large {large}: {good} of {len(sel)} pools perfect, P(no exact | this large set) = {dec(rate)}")
    with open(os.path.join(DATA, "perfect_pools.txt"), "w") as f:
        for p in perfect:
            f.write(" ".join(map(str, p)) + "\n")
    mean_misses = sum(P[p] * counts[p] for p in pools)
    say(f"expected misses per dealt pool = {dec(mean_misses, 4)} of 900")

    say("\n== Worst pools ==")
    say("pool\tmisses\tmax distance\tM(p)\tP(deal)")
    for p in sorted(pools, key=lambda p: (-counts[p], p))[:15]:
        say(f"{p}\t{counts[p]}\t{max(miss[p].values())}\t{checker[p][0]}\t{dec(P[p], 9)}")

    say("\n== Distance when there is no exact answer ==")
    e_d = sum(P[p] * sum(miss[p].values()) for p in pools) / 900 / p_miss
    say(f"E[distance | no exact] = {frac(e_d)} = {dec(e_d, 6)}")
    e_d_all = sum(P[p] * sum(miss[p].values()) for p in pools) / 900
    say(f"E[distance] over all rounds = {frac(e_d_all)} = {dec(e_d_all, 8)}")
    dist_mass, dist_count = Counter(), Counter()
    for p in pools:
        for d in miss[p].values():
            dist_mass[d] += P[p] / 900
            dist_count[d] += 1
    say("d\tinstances\tP(no exact and distance d)\tP(d | no exact)")
    for d in sorted(dist_mass)[:12]:
        say(f"{d}\t{dist_count[d]}\t{dec(dist_mass[d], 9)}\t{dec(dist_mass[d] / p_miss, 6)}")
    tail = [d for d in dist_mass if d > 12]
    say(f">12\t{sum(dist_count[d] for d in tail)}\t{dec(sum(dist_mass[d] for d in tail), 9)}")
    p_far = sum(dist_mass[d] for d in dist_mass if d > 10)
    say(f"P(best answer more than 10 away) = {dec(p_far, 9)}")
    dmax = max(dist_mass)
    worst = [(p, t) for p in pools for t, d in miss[p].items() if d == dmax]
    say(f"max distance {dmax} at {worst}")

    say("\n== Targets ==")
    tm = defaultdict(Fraction)
    tcount = Counter()
    mul_only = Counter()
    mul_only_mass = defaultdict(Fraction)
    for p in pools:
        for t in miss[p]:
            tm[t] += P[p]
            tcount[t] += 1
        for t in checker[p][3]:
            mul_only[t] += 1
            mul_only_mass[t] += P[p]
    with open(os.path.join(DATA, "targets.tsv"), "w") as f:
        f.write("target\tprime\tmissing_pools\tp_no_exact\tp_no_exact_fraction\tmul_only_pools\tp_mul_only\n")
        for t in TARGETS:
            f.write(f"{t}\t{int(is_prime(t))}\t{tcount[t]}\t{dec(tm[t], 9)}\t{frac(tm[t])}\t{mul_only[t]}\t"
                    f"{dec(mul_only_mass[t], 9)}\n")
    order = sorted(TARGETS, key=lambda t: (-tm[t], t))
    say("hardest: " + ", ".join(f"{t} ({dec(tm[t], 5)}, {tcount[t]} pools)" for t in order[:15]))
    say("easiest: " + ", ".join(f"{t} ({dec(tm[t], 7)}, {tcount[t]} pools)" for t in order[::-1][:15]))
    always = [t for t in TARGETS if tcount[t] == 0]
    say(f"targets every pool reaches: {len(always)}: {always}")
    say("mean P(no exact | t) by hundred: " + ", ".join(
        f"{h}s {dec(sum(tm[t] for t in range(h, h + 100)) / 100, 5)}" for h in range(100, 1000, 100)))
    for h in range(100, 1000, 100):
        assert sum(tm[t] for t in range(h, h + 100)) / 100 >= 0
    first = sum(tm[t] for t in range(100, 550)) / 450
    second = sum(tm[t] for t in range(550, 1000)) / 450
    say(f"P(no exact | t < 550) = {dec(first)}, P(no exact | t >= 550) = {dec(second)}")

    say("\n== Value bound ==")
    paper = {p: prod(x + 1 for x in p) - 1 for p in pools}
    psb = {p: product_sum_bound(p) for p in pools}
    say(f"pools where the checker's largest value M(p) equals the max(a*b, a+b) recursion: "
        f"{sum(psb[p] == checker[p][0] for p in pools)} of {len(pools)}")
    say(f"smallest paper bound prod(p_i + 1) - 1 over pools: {min(paper.values())} at "
        f"{min(pools, key=lambda p: paper[p])}; pools with paper bound < 999: {sum(paper[p] < 999 for p in pools)}")
    say(f"smallest M(p): {min(checker[p][0] for p in pools)}; pools with M(p) < 999: "
        f"{[(p, checker[p][0]) for p in pools if checker[p][0] < 999]}")
    oor = sum(1 for p in pools for t in miss[p] if t > checker[p][0])
    oor_mass = sum(P[p] for p in pools for t in miss[p] if t > checker[p][0]) / 900
    say(f"misses above M(p) (out of range): {oor} instances, probability {dec(oor_mass, 9)} "
        f"({dec(oor_mass / p_miss * 100, 4)}% of misses); holes below M(p): {total - oor} instances")
    say("ratio M(p)/999 against misses: mean misses for pools with M(p) in ranges")
    for lo, hi in [(0, 998), (999, 9999), (10000, 99999), (100000, 999999), (1000000, 10 ** 9)]:
        sel = [p for p in pools if lo <= checker[p][0] <= hi]
        if sel:
            m = sum(P[p] * counts[p] for p in sel) / 900 / sum(P[p] for p in sel)
            say(f"  M in [{lo}, {hi}]: {len(sel)} pools, P(no exact | pool in range) = {dec(m)}")
    say("distinct reachable values against misses")
    for lo, hi in [(0, 999), (1000, 1999), (2000, 3999), (4000, 7999), (8000, 15999), (16000, 10 ** 6)]:
        sel = [p for p in pools if lo <= checker[p][1] <= hi]
        if sel:
            m = sum(P[p] * counts[p] for p in sel) / 900 / sum(P[p] for p in sel)
            say(f"  |V| in [{lo}, {hi}]: {len(sel)} pools, P(no exact | pool) = {dec(m)}")

    say("\n== Primes ==")
    primes = [t for t in TARGETS if is_prime(t)]
    comps = [t for t in TARGETS if not is_prime(t)]
    rp = sum(tm[t] for t in primes) / len(primes)
    rc = sum(tm[t] for t in comps) / len(comps)
    say(f"{len(primes)} primes, {len(comps)} composites in 100..999")
    say(f"P(no exact | t prime) = {frac(rp)} = {dec(rp)}; P(no exact | t composite) = {dec(rc)}; ratio {dec(rp / rc, 3)}")
    bad = sum(mul_only[t] for t in primes)
    say(f"prime targets reached only through a final multiplication (must be 0): {bad}")
    assert bad == 0
    # Remove the final-multiplication route from composites to see how much of the gap it explains
    rc_nomul = sum(tm[t] + mul_only_mass[t] for t in comps) / len(comps)
    say(f"P(composite target unreachable without a final multiplication) = {dec(rc_nomul)}")
    say(f"P(reachable composite instance needs a final multiplication) = "
        f"{dec(sum(mul_only_mass[t] for t in comps) / len(comps))}")
    say("by hundred: band, primes, P(miss|prime), P(miss|composite), P(no route without final *|composite)")
    for h in range(100, 1000, 100):
        bp = [t for t in primes if h <= t < h + 100]
        bc = [t for t in comps if h <= t < h + 100]
        say(f"  {h}s\t{len(bp)}\t{dec(sum(tm[t] for t in bp) / len(bp), 5)}\t{dec(sum(tm[t] for t in bc) / len(bc), 5)}"
            f"\t{dec(sum(tm[t] + mul_only_mass[t] for t in bc) / len(bc), 5)}")
    classes = defaultdict(list)
    for t in TARGETS:
        q = largest_prime_factor(t)
        key = "prime" if q == t else ("10-smooth" if q <= 10 else ("largest factor 11-50" if q <= 50 else "largest factor > 50"))
        classes[key].append(t)
    say("by largest prime factor: class, targets, mean P(no exact)")
    for key in ("10-smooth", "largest factor 11-50", "largest factor > 50", "prime"):
        ts = classes[key]
        say(f"  {key}\t{len(ts)}\t{dec(sum(tm[t] for t in ts) / len(ts), 5)}")
    say(f"hardest 50 targets: {sum(is_prime(t) for t in order[:50])} prime; "
        f"{sum(largest_prime_factor(t) > 50 for t in order[:50])} with largest prime factor > 50")

    say("\n== Residues ==")
    for m in (2, 5, 10, 25):
        say(f"mod {m}: " + ", ".join(
            f"{r}:{dec(sum(tm[t] for t in TARGETS if t % m == r) / sum(1 for t in TARGETS if t % m == r), 5)}"
            for r in range(m)))

    say("\n== Pool structure ==")

    def report(label, key):
        groups = defaultdict(list)
        for p in pools:
            groups[key(p)].append(p)
        say(label)
        for k in sorted(groups):
            g = groups[k]
            mass = sum(P[p] for p in g)
            m = sum(P[p] * counts[p] for p in g) / 900 / mass
            say(f"  {k}\t{len(g)} pools\tP(pool)={dec(mass, 5)}\tP(no exact | pool)={dec(m, 5)}\t"
                f"perfect {sum(counts[p] == 0 for p in g)}")

    report("by copies of 1", lambda p: p.count(1))
    report("by number of large", lambda p: ell[p])
    report("by largest small number", lambda p: max(x for x in p if x not in LARGE))
    report("by number of repeated small values", lambda p: sum(1 for v in set(p) if p.count(v) == 2))
    report("by sum of small numbers (bands of 10)",
           lambda p: f"{(sum(x for x in p if x not in LARGE) // 10) * 10:02d}s")

    text = "\n".join(out) + "\n"
    with open(os.path.join(DATA, "analysis.txt"), "w") as f:
        f.write(text)
    print(text)


if __name__ == "__main__":
    main()
