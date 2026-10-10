"""
Check the table solver against hand-worked rounds and the shared reference answers
"""

import os
import re
import unittest

from solver import solve

DATA = os.path.join(os.path.dirname(__file__), "..", "bench", "data")


class SolverTest(unittest.TestCase):
    def test_target_in_pool(self):
        self.assertEqual(solve(100, [1, 2, 3, 4, 5, 100]), (100, "100"))

    def test_outside_table_falls_back(self):
        self.assertEqual(solve(5, [1, 2, 3, 4, 5, 6]), (5, "5"))

    def test_reference_rounds(self):
        # Accept a different expression only when it is as good since the table ignores the order of the pool
        with open(os.path.join(DATA, "rounds1k.txt")) as f:
            rounds = [list(map(int, line.split())) for line in f]
        with open(os.path.join(DATA, "ref1k.tsv")) as f:
            expected = f.read().rstrip("\n").split("\n")
        for (target, *pool), line in zip(rounds, expected):
            ref_value, ref_expr = line.split("\t")
            value, expr = solve(target, pool)
            self.assertEqual(value, int(ref_value))
            self.assertEqual(eval(expr.replace("/", "//")), value)
            self.assertEqual(len(re.findall(r"\d+", expr)), len(re.findall(r"\d+", ref_expr)))


if __name__ == "__main__":
    unittest.main()
