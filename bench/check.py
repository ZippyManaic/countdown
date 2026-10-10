"""
Compare a solver's answers with the reference and count exact matches, equally good ties and real differences
"""

import re
import sys


def numbers_used(expr):
    return len(re.findall(r"\d+", expr))


def main():
    rounds = [list(map(int, line.split())) for line in open(sys.argv[1])]
    # Ignore a final newline since some languages' text output always ends with one
    ref = open(sys.argv[2]).read().rstrip("\n").split("\n")
    got = open(sys.argv[3]).read().rstrip("\n").split("\n")
    if len(got) != len(ref):
        print(f"wrong length {len(got)} vs {len(ref)}")
        return 1
    same = ties = wrong = 0
    for (target, *pool), r, g in zip(rounds, ref, got):
        if r == g:
            same += 1
            continue
        rv, re_ = r.split("\t")
        gv, ge = g.split("\t")
        # Count an answer as a tie when it is as close to the target and uses as many numbers as the reference
        if abs(int(gv) - target) == abs(int(rv) - target) and numbers_used(ge) == numbers_used(re_) and \
                eval(ge.replace("/", "//")) == int(gv):
            ties += 1
        else:
            wrong += 1
    print(f"{same} identical, {ties} ties, {wrong} wrong")
    return 1 if wrong else 0


if __name__ == "__main__":
    sys.exit(main())
