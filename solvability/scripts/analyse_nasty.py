"""
Compare exact solvability per number of large numbers between the standard and the 2010 "nasty" large cards
"""

import os
from collections import defaultdict

from analyse_cats import dec, frac, per_ell, standard_by_ell, write_misses
from common import DATA, LARGE, NASTY, TARGETS, load_checker, nasty_pools


def main():
    standard, std_by_ell = standard_by_ell()
    nasty = load_checker(os.path.join(DATA, "checker_nasty.tsv"))
    write_misses(os.path.join(DATA, "misses_nasty.tsv"), nasty_pools(), nasty)
    # Reuse the 0-large pools since they hold no large card of either set
    nasty.update({p: standard[p] for p in std_by_ell[0]})
    by_ell = defaultdict(list)
    for p in std_by_ell[0] + nasty_pools():
        by_ell[sum(x in NASTY for x in p)].append(p)
    assert {e: len(v) for e, v in by_ell.items()} == {0: 2850, 1: 5808, 2: 3690, 3: 840, 4: 55}

    detail = []
    std_rates, std_targets = per_ell(standard, std_by_ell, LARGE, lambda line: None)
    rates, targets = per_ell(nasty, by_ell, NASTY, detail.append)
    out = ["l\tP(no exact | l) standard\tdecimal\tP(no exact | l) nasty\tdecimal\tnasty minus standard\tnasty easier?"]
    for e in range(5):
        diff = rates[e] - std_rates[e]
        out.append(f"{e}\t{frac(std_rates[e])}\t{dec(std_rates[e], 9)}\t{frac(rates[e])}\t{dec(rates[e], 9)}\t"
                   f"{dec(diff, 9)}\t{'same' if diff == 0 else ('yes' if diff < 0 else 'no')}")
    for label, ells in (("l uniform on 1..2", (1, 2)), ("l uniform on 0..4", range(5)), ("l uniform on 1..4", (1, 2, 3, 4))):
        s = sum(std_rates[e] for e in ells) / len(ells)
        n = sum(rates[e] for e in ells) / len(ells)
        out.append(f"{label}: standard {frac(s)} = {dec(s, 9)}, nasty {frac(n)} = {dec(n, 9)}, "
                   f"ratio nasty/standard {dec(n / s, 4)}")
    for e in range(1, 5):
        worse = sum(1 for t in TARGETS if targets[e][t] > std_targets[e][t])
        better = sum(1 for t in TARGETS if targets[e][t] < std_targets[e][t])
        out.append(f"l={e}: nasty harder on {worse} targets, easier on {better}, equal on {900 - worse - better}")
    text = "\n".join(out) + "\n\n" + "\n".join(detail) + "\n"
    with open(os.path.join(DATA, "analysis_nasty.txt"), "w") as f:
        f.write(text)
    print(text)


if __name__ == "__main__":
    main()
