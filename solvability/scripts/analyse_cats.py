"""
Compute exact solvability per number of large numbers for the full television rules where 0 to 4 large are allowed
"""

import os
from collections import Counter, defaultdict
from fractions import Fraction
from math import comb, prod

from analyse import product_sum_bound
from common import DATA, LARGE, TARGETS, cats_pools, load_checker, load_pools


def conditional_probability(pool, cards):
    """
    Return the probability of dealing this multiset given its number of large numbers drawn from cards
    """
    large = [x for x in pool if x in cards]
    small = [x for x in pool if x not in cards]
    p = Fraction(1, comb(4, len(large)) * comb(20, len(small)))
    for v in set(small):
        p *= comb(2, small.count(v))
    return p


def dec(x, places=6):
    return f"{float(x):.{places}f}"


def frac(x):
    return f"{x.numerator}/{x.denominator}"


def write_misses(path, pools, checker):
    """
    Write per-pool miss lists in the format of misses.tsv
    """
    with open(path, "w") as f:
        f.write("pool\tmiss_count\tmissed_targets\n")
        for p in pools:
            missed = sorted(checker[p][2])
            f.write(f"{' '.join(map(str, p))}\t{len(missed)}\t{','.join(map(str, missed))}\n")


def per_ell(checker, by_ell, cards, say):
    """
    Report exact statistics for each number of large cards and return {l: P(no exact | l)} and per-target rates
    """
    rates, target_rates = {}, {}
    say("l\tpools\tP(no exact | l)\tdecimal\tuniform instances\tuniform decimal\tperfect pools\tP(perfect | l)\t"
        "E[d | miss]\tmax d\tmax M(p)\tmin M(p)\tout of range\tholes")
    for e in sorted(by_ell):
        pools = by_ell[e]
        P = {p: conditional_probability(p, cards) for p in pools}
        assert sum(P.values()) == 1
        miss = {p: checker[p][2] for p in pools}
        rate = sum(P[p] * len(miss[p]) for p in pools) / 900
        rates[e] = rate
        total = sum(len(miss[p]) for p in pools)
        uni = Fraction(total, 900 * len(pools))
        perfect = [p for p in pools if not miss[p]]
        e_d = sum(P[p] * sum(miss[p].values()) for p in pools) / 900 / rate
        dmax = max(d for p in pools for d in miss[p].values())
        oor = sum(1 for p in pools for t in miss[p] if t > checker[p][0])
        say(f"{e}\t{len(pools)}\t{frac(rate)}\t{dec(rate, 9)}\t{total:,}/{900 * len(pools):,} = {frac(uni)}\t"
            f"{dec(uni, 6)}\t{len(perfect)}\t{dec(sum(P[p] for p in perfect), 6)}\t{dec(e_d, 4)}\t{dmax}\t"
            f"{max(checker[p][0] for p in pools)}\t{min(checker[p][0] for p in pools)}\t{oor}\t{total - oor}")

    for e in sorted(by_ell):
        pools = by_ell[e]
        P = {p: conditional_probability(p, cards) for p in pools}
        miss = {p: checker[p][2] for p in pools}
        say(f"\n== {e} large from {cards} ==")
        paper = min(prod(x + 1 for x in p) - 1 for p in pools)
        say(f"largest reachable value {max(checker[p][0] for p in pools):,} at "
            f"{max(pools, key=lambda p: checker[p][0])}; smallest paper bound prod(p_i + 1) - 1 is {paper:,}; "
            f"pools with M(p) >= 2^27: {sum(checker[p][0] >= 2 ** 27 for p in pools)}")
        same = sum(product_sum_bound(p) == checker[p][0] for p in pools)
        say(f"pools whose M(p) equals the max(a*b, a+b) recursion: {same} of {len(pools)}")
        small_m = sorted((checker[p][0], p) for p in pools if checker[p][0] < 999)
        say(f"pools with M(p) < 999: {len(small_m)} {small_m[:10]}")
        say("worst pools (pool, misses, max distance, M(p)):")
        for p in sorted(pools, key=lambda p: (-len(miss[p]), p))[:8]:
            say(f"  {p}\t{len(miss[p])}\t{max(miss[p].values())}\t{checker[p][0]}")
        tm = defaultdict(Fraction)
        tc = Counter()
        for p in pools:
            for t in miss[p]:
                tm[t] += P[p]
                tc[t] += 1
        target_rates[e] = tm
        order = sorted(TARGETS, key=lambda t: (-tm[t], t))
        say("hardest targets (P(no exact | t, l), pools missing): " +
            ", ".join(f"{t} ({dec(tm[t], 4)}, {tc[t]})" for t in order[:10]))
        always = [t for t in TARGETS if tc[t] == 0]
        say(f"targets every {e}-large pool reaches: {len(always)}" + (f": {always}" if len(always) <= 40 else ""))
        say("P(no exact | t, l) by hundred: " +
            ", ".join(f"{h}s {dec(sum(tm[t] for t in range(h, h + 100)) / 100, 5)}" for h in range(100, 1000, 100)))
    return rates, target_rates


def standard_by_ell():
    """
    Return the checker results and the standard pools grouped by number of large cards for l = 0..4
    """
    checker = load_checker()
    checker.update(load_checker(os.path.join(DATA, "checker_cats.tsv")))
    by_ell = defaultdict(list)
    for p in load_pools() + cats_pools():
        by_ell[sum(x in LARGE for x in p)].append(p)
    assert {e: len(v) for e, v in by_ell.items()} == {0: 2850, 1: 5808, 2: 3690, 3: 840, 4: 55}
    return checker, by_ell


def main():
    checker, by_ell = standard_by_ell()
    write_misses(os.path.join(DATA, "misses_cats.tsv"), cats_pools(), checker)
    out = []
    rates, _ = per_ell(checker, by_ell, LARGE, out.append)
    avg = sum(rates.values()) / 5
    out.insert(0, f"P(no exact) with l uniform on 0..4 = {frac(avg)} = {dec(avg, 12)}")
    main_game = (rates[1] + rates[2]) / 2
    out.insert(1, f"P(no exact) with l uniform on 1..2 (main study) = {frac(main_game)} = {dec(main_game, 12)}\n")
    text = "\n".join(out) + "\n"
    with open(os.path.join(DATA, "analysis_cats.txt"), "w") as f:
        f.write(text)
    print(text)


if __name__ == "__main__":
    main()
