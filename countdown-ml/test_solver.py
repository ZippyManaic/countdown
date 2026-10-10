"""
Check the transformer-guided solver against hand-worked rounds and the shared reference answers
"""

import os
import re
import unittest

from solver import solve, solve_many

DATA = os.path.join(os.path.dirname(__file__), "..", "bench", "data")


class SolverTest(unittest.TestCase):
    def test_target_in_pool(self):
        self.assertEqual(solve(100, [1, 2, 3, 4, 5, 100]), (100, "100"))

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
