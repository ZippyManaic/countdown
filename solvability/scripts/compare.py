"""
Compare exact/miss status and distance for every instance across the checker, countdown-c and answers.bin
"""

import sys

import numpy as np

from common import DATA, TARGETS, cats_pools, load_answers_values, load_checker, load_pools, nasty_pools


def main():
    # Pass "cats" or "nasty" to compare the extra pools, which have no answers.bin
    mode = sys.argv[1] if len(sys.argv) > 1 else "main"
    cats = mode != "main"
    if cats:
        checker = load_checker(f"{DATA}/checker_{mode}.tsv")
        pools = cats_pools() if mode == "cats" else nasty_pools()
        expected = 3745 if mode == "cats" else 10393
    else:
        checker = load_checker()
        pools = load_pools()
        expected = 9498
    assert len(pools) == expected and len(set(pools)) == expected, f"pool list is not {expected:,} distinct pools"
    assert set(pools) == set(checker), "checker and pools.py enumerate different pools"
    targets = np.array(TARGETS, dtype=np.int64)
    n = len(pools) * len(targets)

    # Build the checker's distance for every instance in the table's order with zero meaning exact
    check_d = np.zeros(n, dtype=np.int64)
    for i, pool in enumerate(pools):
        for t, d in checker[pool][2].items():
            check_d[i * 900 + t - 100] = d

    c_values = np.fromfile(f"{DATA}/c_values{'_' + mode if cats else ''}.bin", dtype="<u4").astype(np.int64)
    assert len(c_values) == n
    all_targets = np.tile(targets, len(pools))
    c_d = np.abs(c_values - all_targets)
    sources = [("countdown-c", c_d)]
    if not cats:
        table_values = load_answers_values()
        assert len(table_values) == n
        table_d = np.abs(table_values - all_targets)
        sources.append(("answers.bin", table_d))

    failed = False
    for name, other in sources:
        status = np.flatnonzero((other == 0) != (check_d == 0))
        dist = np.flatnonzero(other != check_d)
        print(f"checker vs {name}: {len(status)} exact/miss disagreements, {len(dist)} distance disagreements")
        for i in dist[:50]:
            print(f"  pool {pools[i // 900]} target {100 + i % 900}: checker d={check_d[i]}, {name} d={other[i]}")
        failed |= len(dist) > 0
    if cats:
        print(f"misses: checker {int(np.sum(check_d > 0)):,}, countdown-c {int(np.sum(c_d > 0)):,} of {n:,}")
        return 1 if failed else 0
    status = np.flatnonzero((c_d == 0) != (table_d == 0))
    dist = np.flatnonzero(c_d != table_d)
    print(f"countdown-c vs answers.bin: {len(status)} exact/miss disagreements, {len(dist)} distance disagreements")
    failed |= len(dist) > 0
    same_value = int(np.sum(c_values == table_values))
    print(f"countdown-c and answers.bin return the same value on {same_value:,} of {n:,} instances")
    print(f"misses: checker {int(np.sum(check_d > 0)):,}, countdown-c {int(np.sum(c_d > 0)):,}, "
          f"answers.bin {int(np.sum(table_d > 0)):,} of {n:,}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
