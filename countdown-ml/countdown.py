#!/usr/bin/env python3
"""
Generate a Countdown numbers round and work out whether it can be solved with a transformer proposing answers and an exact search checking them
"""

import random
import sys

from solver import solve

# Map each mode to its large cards, with nasty-cats using the cards of the 2010 specials
LARGE_NUMBERS = {"standard": [25, 50, 75, 100], "cats": [25, 50, 75, 100], "nasty": [12, 37, 62, 87]}
# Hold two cards of each small number to match the game's deck
SMALL_NUMBERS = list(range(1, 11)) * 2
USAGE = "usage: countdown.py [standard|cats|nasty] [LARGE]"


def generate_round(mode="standard", large_count=None):
    """
    Return a random target and six numbers with one or two large in standard mode and none to four otherwise
    """
    target = random.randint(100, 999)
    if large_count is None:
        large_count = random.choice([1, 2]) if mode == "standard" else random.randint(0, 4)
    small = random.sample(SMALL_NUMBERS, 6 - large_count)
    # Sample without replacement since each large number appears only once in the game
    large = random.sample(LARGE_NUMBERS[mode], large_count)
    return target, small + large


def parse_args(args):
    """
    Return the mode and fixed large count from the command line, or None when the arguments are invalid
    """
    if len(args) > 2:
        return None
    mode = args[0] if args else "standard"
    if mode not in LARGE_NUMBERS:
        return None
    if len(args) < 2:
        return mode, None
    allowed = ("1", "2") if mode == "standard" else ("0", "1", "2", "3", "4")
    return (mode, int(args[1])) if args[1] in allowed else None


def main():
    parsed = parse_args(sys.argv[1:])
    if parsed is None:
        print(USAGE, file=sys.stderr)
        return 2
    target, pool = generate_round(*parsed)
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
