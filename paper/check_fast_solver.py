#!/usr/bin/env python3
"""
Recompute the numerical inequalities of the note "Countdown: Faster Exact Search via Three-Way Joins"
"""

from fractions import Fraction as F
from math import log, log2


def entropy_q(theta):
    return (-theta * log(theta) - (1 - theta) * log(1 - theta) + theta * log(9)) / log(4)


def check(name, ok, detail):
    print(f"{'ok  ' if ok else 'FAIL'} {name}: {detail}")
    return ok


def main():
    ok = True

    # Check the balanced refinement of Section 2
    theta, alpha, eta, beta = 10513 / 100000, 1417 / 25000, 343 / 100000, 213 / 8000
    gamma = theta * log(20 / 9) / log(4)
    q = entropy_q(theta)
    r = log(4) / (21 * log(10) - 0.5 * (21 * log(21) - 20 * log(20)) - 20 * log(3) + theta * log(20 / 9))
    ok &= check("2 beta + eta = alpha", F(213, 8000) * 2 + F(343, 100000) == F(1417, 25000), "exact")
    ok &= check("gamma > 0.06055", gamma > 0.06055, f"gamma = {gamma:.9f}, margin {gamma - 0.06055:.2e}")
    ok &= check("q < 0.40916", q < 0.40916, f"q = {q:.9f}, margin {0.40916 - q:.2e}")
    ok &= check("R > alpha", r > alpha, f"R = {r:.9f}, margin {r - alpha:.2e}")
    ok &= check("alpha gamma > eta", alpha * 0.06055 > eta, f"{alpha * 0.06055:.9f} > {eta}")
    ok &= check("beta - alpha q > eta", beta - alpha * 0.40916 > eta, f"{beta - alpha * 0.40916:.9f} > {eta}")
    tau = F(2) - F(343, 100000)
    ok &= check("tau / (tau + 1) = 199657/299657", tau / (tau + 1) == F(199657, 299657),
                f"{float(tau / (tau + 1)):.10f}")

    # Check the asymmetric bound of Lemma 3.1
    theta, alpha, g, h = 3 / 25, 129 / 2500, 399 / 100000, 93 / 20000
    gamma = theta * log(22 / 9) / log(4)
    q = entropy_q(theta)
    ok &= check("Lemma 3.1 gamma > 0.07735", gamma > 0.07735, f"gamma = {gamma:.9f}")
    ok &= check("Lemma 3.1 q < 0.4549", q < 0.4549, f"q = {q:.9f}")
    ok &= check("alpha gamma > g", alpha * 0.07735 > g, f"{alpha * 0.07735:.9f} > {g}")
    ok &= check("alpha (1 - 2q) > h", alpha * (1 - 2 * 0.4549) > h, f"{alpha * (1 - 2 * 0.4549):.9f} > {h}")

    # Check the two conditions closing Theorem 3.2 and the width of its hard case
    g, h, d, k = F(399, 100000), F(93, 20000), F(343, 100000), F(666223, 1000000)
    ok &= check("(2 - g)/(3 - g) < K", (2 - g) / (3 - g) < k, f"{float((2 - g) / (3 - g)):.10f}")
    ok &= check("(4 - 3d + h)/(6 - 4d + 2h) < K", (4 - 3 * d + h) / (6 - 4 * d + 2 * h) < k,
                f"{float((4 - 3 * d + h) / (6 - 4 * d + 2 * h)):.10f}")
    print(f"     hard case needs {float(k / (2 - d)):.6f} < a < {float(1 - k):.6f}")

    # Show the size of the improvement for the six numbers of the game
    e = 6 * log2(6)
    print(f"     n = 6: n log2 n = {e:.3f}, 2^((2/3 - K) n log2 n) = {2 ** ((2 / 3 - float(k)) * e):.4f}")
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
