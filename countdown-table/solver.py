"""
Answer Countdown numbers rounds by looking them up in a table precomputed for every pool the game can deal
"""

import importlib.util
import mmap
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
# Find the pool list beside this file even when loaded by path from elsewhere
sys.path.insert(0, HERE)
from pools import TARGETS, pools  # noqa: E402

TABLE = os.environ.get("COUNTDOWN_TABLE", os.path.join(HERE, "answers.bin"))

# Map each sorted pool to its row of answers, one per target
ROWS = {pool: row for row, pool in enumerate(pools())}
FIRST_TARGET = TARGETS.start
WIDTH = len(TARGETS)

# Map the file so a lookup only reads the pages it touches rather than loading the whole table
with open(TABLE, "rb") as _f:
    _table = mmap.mmap(_f.fileno(), 0, access=mmap.ACCESS_READ)
if _table[:4] != b"CDT1":
    raise ValueError(f"{TABLE} is not an answer table")
(_count,) = struct.unpack_from("<I", _table, 4)
OFFSETS = 8
VALUES = OFFSETS + 4 * (_count + 1)
TEXT = VALUES + 2 * _count
_unpack_span = struct.Struct("<II").unpack_from
_unpack_value = struct.Struct("<H").unpack_from

_fallback = None


def fallback(target, pool):
    """
    Solve a round the table does not cover with the plain Python solver
    """
    global _fallback
    if _fallback is None:
        spec = importlib.util.spec_from_file_location("plain", os.path.join(HERE, "..", "countdown.py"))
        _fallback = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(_fallback)
    return _fallback.solve(target, list(pool))


def solve(target, pool):
    """
    Return the simplest expression that hits the target or gets closest to it, with its value
    """
    row = ROWS.get(tuple(sorted(pool)))
    if row is None or target not in TARGETS:
        return fallback(target, pool)
    i = row * WIDTH + target - FIRST_TARGET
    start, end = _unpack_span(_table, OFFSETS + 4 * i)
    return _unpack_value(_table, VALUES + 2 * i)[0], _table[TEXT + start:TEXT + end].decode("ascii")
