"""
List every pool the game can deal as a sorted tuple in the fixed order the answer table uses
"""

from itertools import combinations, combinations_with_replacement

LARGE_NUMBERS = [25, 50, 75, 100]
TARGETS = range(100, 1000)


def pools():
    """
    Return every distinct pool of one or two large numbers and small numbers with at most two of each
    """
    out = []
    for large_count in (1, 2):
        for large in combinations(LARGE_NUMBERS, large_count):
            for small in combinations_with_replacement(range(1, 11), 6 - large_count):
                # Allow each small number at most twice since the deck holds two of each
                if all(small.count(n) <= 2 for n in small):
                    out.append(tuple(sorted(small + large)))
    return out
