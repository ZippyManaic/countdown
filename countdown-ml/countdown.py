#!/usr/bin/env python3
"""
Generate a Countdown numbers round and work out whether it can be solved with a transformer proposing answers and an exact search checking them
"""

import random
import sys

from solver import solve

LARGE_NUMBERS = [25, 50, 75, 100]
# Hold two cards of each small number to match the game's deck
SMALL_NUMBERS = list(range(1, 11)) * 2


def generate_round():
    """
    Return a random target and a pool of six numbers with either one or two large numbers
    """
    target = random.randint(100, 999)
    large_count = random.choice([1, 2])
    small = random.sample(SMALL_NUMBERS, 6 - large_count)
    # Sample without replacement since each large number appears only once in the game
    large = random.sample(LARGE_NUMBERS, large_count)
    return target, small + large


def main():
    target, pool = generate_round()
    print(f"Target: {target}")
    print(f"Pool:   {' '.join(str(n) for n in pool)}")

    value, expr = solve(target, pool)
    if value == target:
        print(f"Solved: {expr} = {value}")
        return 0
    print(f"No exact solution, closest is {expr} = {value} ({abs(target - value)} away)")
    return 1


if __name__ == "__main__":
    sys.exit(main())
