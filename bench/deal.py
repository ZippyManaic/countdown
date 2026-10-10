#!/usr/bin/env python3
"""
Deal benchmark rounds for the cats and nasty-cats modes, where the player chooses from none to four large numbers

Usage: bench/deal.py cats|nasty COUNT SEED > rounds.txt
"""

import random
import sys

LARGE = {"cats": [25, 50, 75, 100], "nasty": [12, 37, 62, 87]}
# Hold two cards of each small number to match the game's deck
SMALL_NUMBERS = list(range(1, 11)) * 2


def main():
    mode, count, seed = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
    rng = random.Random(seed)
    for _ in range(count):
        target = rng.randint(100, 999)
        # Choose the number of large numbers uniformly as Table tab:cats in the paper assumes
        large_count = rng.randint(0, 4)
        pool = rng.sample(SMALL_NUMBERS, 6 - large_count) + rng.sample(LARGE[mode], large_count)
        print(target, *pool)


if __name__ == "__main__":
    main()
