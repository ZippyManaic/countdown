"""
Check the dealer in every mode and the transformer-guided solver against hand-worked rounds and the shared reference answers
"""

import contextlib
import io
import os
import random
import re
import unittest
from collections import Counter
from unittest import mock

import countdown
from solver import solve, solve_many

DATA = os.path.join(os.path.dirname(__file__), "..", "bench", "data")


class DealerTest(unittest.TestCase):
    def check_round(self, mode, target, pool, counts):
        self.assertTrue(100 <= target <= 999)
        self.assertEqual(len(pool), 6)
        large = [n for n in pool if n > 10]
        self.assertIn(len(large), counts)
        self.assertTrue(set(large) <= set(countdown.LARGE_NUMBERS[mode]))
        self.assertEqual(len(set(large)), len(large))
        # Allow each small number at most twice since the deck holds two of each
        self.assertTrue(all(c <= 2 for n, c in Counter(pool).items() if n <= 10))
        return len(large)

    def test_modes(self):
        random.seed(1)
        for mode, counts in (("standard", {1, 2}), ("cats", {0, 1, 2, 3, 4}), ("nasty", {0, 1, 2, 3, 4})):
            seen = {self.check_round(mode, *countdown.generate_round(mode), counts) for _ in range(2000)}
            self.assertEqual(seen, counts, mode)

    def test_fixed_large(self):
        for mode in ("cats", "nasty"):
            for k in range(5):
                self.assertEqual(self.check_round(mode, *countdown.generate_round(mode, k), {k}), k)

    def test_arguments(self):
        self.assertEqual(countdown.parse_args([]), ("standard", None))
        self.assertEqual(countdown.parse_args(["nasty", "4"]), ("nasty", 4))
        self.assertEqual(countdown.parse_args(["cats", "0"]), ("cats", 0))
        for bad in (["standard", "3"], ["cats", "5"], ["dogs"], ["cats", "1", "2"], ["cats", "x"]):
            self.assertIsNone(countdown.parse_args(bad), bad)

    def test_solves_large_pool(self):
        # Deal a cats round with four large numbers whose products need the widest packing and expect it solved
        out = io.StringIO()
        with mock.patch.object(countdown, "generate_round", return_value=(999, [10, 10, 25, 50, 75, 100])), \
                mock.patch("sys.argv", ["countdown.py", "cats", "4"]), contextlib.redirect_stdout(out):
            self.assertEqual(countdown.main(), 0)
        self.assertTrue(out.getvalue().endswith("Solved: (((75 + 25) * 100) - 10) / 10 = 999\n"))


class SolverTest(unittest.TestCase):
    def test_cats_rounds(self):
        self.assertEqual(solve(999, [10, 10, 25, 50, 75, 100]), (999, "(((75 + 25) * 100) - 10) / 10"))
        self.assertEqual(solve(100, [1, 1, 2, 2, 3, 3]), (81, "(((2 + 1) * (2 + 1)) * 3) * 3"))
        self.assertEqual(solve(999, [2, 3, 87, 62, 37, 12]), (999, "37 * ((87 / 3) - 2)"))

    def test_target_in_pool(self):
        self.assertEqual(solve(100, [1, 2, 3, 4, 5, 100]), (100, "100"))

    def test_lone_number(self):
        self.assertEqual(solve(100, [7]), (7, "7"))
        self.assertEqual(solve(7, [7]), (7, "7"))

    def test_reference_rounds(self):
        # Accept a different expression only when it is as good since the model may pick another of the same length
        with open(os.path.join(DATA, "rounds1k.txt")) as f:
            rounds = [list(map(int, line.split())) for line in f]
        with open(os.path.join(DATA, "ref1k.tsv")) as f:
            expected = f.read().rstrip("\n").split("\n")
        answers = solve_many([(target, pool) for target, *pool in rounds])
        for line, (value, expr) in zip(expected, answers):
            ref_value, ref_expr = line.split("\t")
            self.assertEqual(value, int(ref_value))
            self.assertEqual(eval(expr.replace("/", "//")), value)
            self.assertEqual(len(re.findall(r"\d+", expr)), len(re.findall(r"\d+", ref_expr)))


if __name__ == "__main__":
    unittest.main()
