"""
Check the PyTorch solver against hand-worked rounds and the shared reference answers
"""

import os
import unittest

from solver import solve, solve_many

DATA = os.path.join(os.path.dirname(__file__), "..", "bench", "data")


class SolverTest(unittest.TestCase):
    def test_target_in_pool(self):
        self.assertEqual(solve(100, [1, 2, 3, 4, 5, 100]), (100, "100"))

    def test_two_numbers(self):
        self.assertEqual(solve(125, [1, 2, 3, 4, 100, 25]), (125, "100 + 25"))

    def test_unreachable_gets_closest(self):
        value, expr = solve(999, [1, 1, 2, 2, 3, 25])
        self.assertNotEqual(value, 999)
        self.assertEqual(eval(expr), value)

    def test_reference_rounds(self):
        with open(os.path.join(DATA, "rounds1k.txt")) as f:
            rounds = [(target, pool) for target, *pool in (map(int, line.split()) for line in f)]
        with open(os.path.join(DATA, "ref1k.tsv")) as f:
            expected = f.read().rstrip("\n").split("\n")
        got = [f"{value}\t{expr}" for value, expr in solve_many(rounds)]
        self.assertEqual(got, expected)


if __name__ == "__main__":
    unittest.main()
