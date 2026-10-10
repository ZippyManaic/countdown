"""
Load the checker's per-pool results, the pool order and the exact deal probabilities shared by the analysis scripts
"""

import os
import struct
from fractions import Fraction
from math import comb

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
DATA = os.path.join(HERE, "..", "data")
TARGETS = range(100, 1000)
LARGE = (25, 50, 75, 100)
NASTY = (12, 37, 62, 87)


def load_checker(path=os.path.join(DATA, "checker.tsv")):
    """
    Return a dict from sorted pool tuple to (max value, distinct values, {missed target: distance}, mul-only targets)
    """
    out = {}
    with open(path) as f:
        next(f)
        for line in f:
            pool, largest, distinct, misses, mul_only = line.rstrip("\n").split("\t")
            key = tuple(int(x) for x in pool.split())
            missed = {}
            if misses:
                for item in misses.split(","):
                    t, d = item.split(":")
                    missed[int(t)] = int(d)
            mul = {int(x) for x in mul_only.split(",")} if mul_only else set()
            out[key] = (int(largest), int(distinct), missed, mul)
    return out


def load_pools(path=os.path.join(DATA, "pools.txt")):
    """
    Return the pools in the answer table's order as sorted tuples
    """
    with open(path) as f:
        return [tuple(int(x) for x in line.split()) for line in f if line.strip()]


def load_answers_values(path=os.path.join(ROOT, "countdown-table", "answers.bin")):
    """
    Return the best values stored in answers.bin as a numpy array in pool-major, target-minor order
    """
    with open(path, "rb") as f:
        head = f.read(8)
        assert head[:4] == b"CDT1"
        (n,) = struct.unpack("<I", head[4:])
        f.seek(8 + 4 * (n + 1))
        values = np.frombuffer(f.read(2 * n), dtype="<u2").astype(np.int64)
    return values


def load_answers_texts(path=os.path.join(ROOT, "countdown-table", "answers.bin")):
    """
    Return a function giving the expression text stored in answers.bin for instance index i
    """
    data = open(path, "rb").read()
    (n,) = struct.unpack("<I", data[4:8])
    offsets = np.frombuffer(data, dtype="<u4", count=n + 1, offset=8)
    base = 8 + 4 * (n + 1) + 2 * n
    return n, lambda i: data[base + int(offsets[i]):base + int(offsets[i + 1])].decode("ascii")


def deal_probability(pool):
    """
    Return the exact probability that the dealer deals this multiset, in any order
    """
    large = [x for x in pool if x in LARGE]
    small = [x for x in pool if x not in LARGE]
    k = len(small)
    p = Fraction(1, 2) / comb(4, len(large)) / comb(20, k)
    for v in set(small):
        p *= comb(2, small.count(v))
    return p


def cats_pools(large_counts=(0, 3, 4), cards=LARGE):
    """
    Return the pools with the given numbers of large cards drawn from the given set, ordered like pools.py
    """
    from itertools import combinations, combinations_with_replacement
    out = []
    for large_count in large_counts:
        for large in combinations(cards, large_count):
            for small in combinations_with_replacement(range(1, 11), 6 - large_count):
                if all(small.count(n) <= 2 for n in small):
                    out.append(tuple(sorted(small + large)))
    return out


def nasty_pools():
    """
    Return the 1- to 4-large pools using the 2010 special-episode large cards 12, 37, 62 and 87
    """
    return cats_pools((1, 2, 3, 4), NASTY)
