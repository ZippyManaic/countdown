"""
Evaluate every countdown-c answer for the cats or nasty pools, exact or not, and check it is legal with the reported value
"""

import os
import sys
from collections import Counter

from common import DATA, TARGETS
from verify_certificates import Illegal, evaluate, open_text


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else "cats"
    path = os.path.join(DATA, f"c_values_{mode}.txt.gz")
    pools = [tuple(int(x) for x in line.split()) for line in open(os.path.join(DATA, f"pools_{mode}.txt"))]
    checked = bad = 0
    with open_text(path) as f:
        for pool in pools:
            for t in TARGETS:
                value, text = f.readline().rstrip("\n").split("\t")
                checked += 1
                try:
                    got, leaves = evaluate(text)
                    if got != int(value) or leaves - Counter(pool):
                        raise Illegal(f"value {got} or leaves {dict(leaves)} do not match")
                except Illegal as e:
                    bad += 1
                    print("  BAD", pool, t, text, e)
    print(f"{path}: {checked:,} countdown-c answers evaluated, {bad} illegal or with the wrong value")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
