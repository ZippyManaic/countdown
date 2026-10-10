#!/usr/bin/env python3
"""Write one batched job per pool with misses for every mode, so one UNSAT proof covers all of a pool's misses"""

import os

HERE = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.join(HERE, "..", "data")
# Map each mode to its miss table, which between them hold every distinct pool exactly once
MODES = {"standard": "misses.tsv", "cats": "misses_cats.tsv", "nasty": "misses_nasty.tsv"}


def main():
    for mode, name in MODES.items():
        rows = []
        for line in open(os.path.join(DATA, name)).readlines()[1:]:
            pool, count, targets = line.rstrip("\n").split("\t")
            if int(count):
                rows.append(f"{mode}_{pool.replace(' ', '_')}\t{pool}\t{targets}\tunsat\n")
        with open(os.path.join(HERE, "jobs", f"full_{mode}.tsv"), "w") as f:
            f.writelines(rows)
        print(mode, len(rows), "jobs")


if __name__ == "__main__":
    main()
