#!/usr/bin/env python3
"""
Generate a Countdown numbers round and work out whether it can be solved
"""

import random
import sys

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


def combine(x, y):
    """
    Return every legal (value, operator) from combining a larger number x with a smaller number y under Countdown rules
    """
    results = [(x + y, "+")]
    # Skip a zero result since every intermediate value must be a positive integer
    if x > y:
        results.append((x - y, "-"))
    # Skip multiplying by one as it never produces a new value
    if y != 1:
        results.append((x * y, "*"))
        if x % y == 0:
            results.append((x // y, "/"))
    return results


def render(reachable, value, origin):
    """
    Rebuild the expression for a value by following its origins back to the pool
    """
    if origin is None:
        return str(value)
    op, larger_mask, larger, smaller_mask, smaller = origin
    left = render(reachable, larger, reachable[larger_mask][larger])
    right = render(reachable, smaller, reachable[smaller_mask][smaller])
    return f"({left} {op} {right})"


def solve(target, pool):
    """
    Return the simplest expression that hits the target or gets closest to it, with its value
    """
    # Map each subset of the pool (as a bitmask) to every value it can make and how the first one found was made
    reachable = {}
    full = (1 << len(pool)) - 1
    # Track the closest value from the whole pool separately since no larger subset is built from it
    whole = None
    whole_distance = float("inf")
    for mask in range(1, full + 1):
        if mask & (mask - 1) == 0:
            reachable[mask] = {pool[mask.bit_length() - 1]: None}
            continue
        values = {}
        # Visit each split of the subset into two non-empty halves once
        left = (mask - 1) & mask
        while left:
            right = mask ^ left
            if left < right:
                for a in reachable[left]:
                    for b in reachable[right]:
                        if a >= b:
                            larger_mask, x, smaller_mask, y = left, a, right, b
                        else:
                            larger_mask, x, smaller_mask, y = right, b, left, a
                        if mask == full:
                            for value, op in combine(x, y):
                                distance = abs(target - value)
                                if distance < whole_distance:
                                    whole_distance = distance
                                    whole = (value, (op, larger_mask, x, smaller_mask, y))
                        else:
                            for value, op in combine(x, y):
                                if value not in values:
                                    values[value] = (op, larger_mask, x, smaller_mask, y)
            left = (left - 1) & mask
        reachable[mask] = values

    # Rank by distance from the target then by how many numbers are used so the simplest answer wins
    value, origin = min(
        ((v, o, bin(m).count("1")) for m, values in reachable.items() for v, o in values.items()),
        key=lambda c: (abs(target - c[0]), c[2]),
    )[:2]
    # Fall back to the whole pool only when it gets strictly closer as it uses the most numbers
    if whole is not None and abs(target - whole[0]) < abs(target - value):
        value, origin = whole

    expr = render(reachable, value, origin)
    # Strip the redundant outermost brackets for display
    if expr.startswith("(") and expr.endswith(")"):
        expr = expr[1:-1]
    return value, expr


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
