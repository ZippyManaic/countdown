"""
Re-verify solvability certificates by evaluating each expression under the paper's legality rules
"""

import gzip
import os
import re
import sys
from collections import Counter
from multiprocessing import Pool

from common import DATA, TARGETS, load_answers_texts, load_pools

TOKEN = re.compile(r"\s*(\d+|[-+*/()])")


class Illegal(Exception):
    pass


def tokenise(text):
    """
    Split an expression into numbers, operators and brackets and reject anything else
    """
    tokens, at = [], 0
    text = text.strip()
    while at < len(text):
        m = TOKEN.match(text, at)
        if not m:
            raise Illegal(f"bad character at {at}")
        tokens.append(m.group(1))
        at = m.end()
    return tokens


def evaluate(text):
    """
    Return the value and leaf multiset of a binary expression after checking every step is legal
    """
    tokens = tokenise(text)
    pos = 0
    leaves = []

    def atom():
        nonlocal pos
        if pos >= len(tokens):
            raise Illegal("unexpected end")
        tok = tokens[pos]
        pos += 1
        if tok == "(":
            value = node()
            if pos >= len(tokens) or tokens[pos] != ")":
                raise Illegal("missing close bracket")
            pos += 1
            return value
        if tok.isdigit():
            leaves.append(int(tok))
            return int(tok)
        raise Illegal(f"unexpected {tok}")

    def node():
        nonlocal pos
        x = atom()
        if pos < len(tokens) and tokens[pos] in "+-*/":
            op = tokens[pos]
            pos += 1
            y = atom()
            # Apply the paper's operation table with the larger operand written first
            if x < y:
                raise Illegal(f"smaller operand first in {x} {op} {y}")
            if op == "+":
                return x + y
            if op == "-":
                if x == y:
                    raise Illegal("zero intermediate")
                return x - y
            if y == 1:
                raise Illegal(f"{op} by one")
            if op == "*":
                return x * y
            if x % y:
                raise Illegal(f"inexact division {x} / {y}")
            return x // y
        return x

    value = node()
    if pos != len(tokens):
        raise Illegal("trailing tokens")
    return value, Counter(leaves)


def check(job):
    """
    Return the pool, the targets it certifies and a list of failures for one pool's certificates
    """
    pool, items = job
    have = Counter(pool)
    bad = []
    certified = set()
    for target, text in items:
        try:
            value, leaves = evaluate(text)
            if value != target:
                raise Illegal(f"value {value} is not the target")
            if leaves - have:
                raise Illegal(f"uses numbers not in the pool: {dict(leaves - have)}")
            certified.add(target)
        except Illegal as e:
            bad.append((pool, target, text, str(e)))
    return pool, certified, bad


def open_text(path):
    """
    Open a text file for reading whether or not it is gzipped
    """
    return gzip.open(path, "rt") if path.endswith(".gz") else open(path)


def certificate_jobs(path):
    """
    Yield (pool, [(target, expression)]) groups from a certificate file
    """
    pool, items = None, []
    with open_text(path) as f:
        for line in f:
            if line.startswith("#"):
                if pool is not None:
                    yield pool, items
                pool, items = tuple(int(x) for x in line[1:].split()), []
            else:
                t, text = line.rstrip("\n").split("\t")
                items.append((int(t), text))
    if pool is not None:
        yield pool, items


def answers_jobs():
    """
    Yield (pool, [(target, expression)]) groups for every exact answer in answers.bin
    """
    from common import load_answers_values
    values = load_answers_values()
    _, text = load_answers_texts()
    for i, pool in enumerate(load_pools()):
        items = [(t, text(i * 900 + t - 100)) for t in TARGETS if values[i * 900 + t - 100] == t]
        yield pool, items


def load_misses(path=os.path.join(DATA, "misses.tsv")):
    """
    Return a dict from sorted pool tuple to its set of unreachable targets as listed in misses.tsv
    """
    out = {}
    with open(path) as f:
        next(f)
        for line in f:
            pool, _, missed = line.rstrip("\n").split("\t")
            out[tuple(int(x) for x in pool.split())] = {int(t) for t in missed.split(",")} if missed else set()
    return out


def c_text_jobs(texts, pools):
    """
    Yield (pool, [(target, expression)]) groups for the exact answers in a countdown-c value and text dump
    """
    with open_text(texts) as f:
        for pool in pools:
            items = []
            for t in TARGETS:
                value, text = f.readline().rstrip("\n").split("\t")
                if int(value) == t:
                    items.append((t, text))
            yield pool, items


USAGE = """usage: verify_certificates.py CERTIFICATES[.gz] [MISSES.tsv]
       verify_certificates.py --answers
       verify_certificates.py --c-texts C_VALUES.txt POOLS.txt MISSES.tsv"""


def main():
    # Stay off CPUs 24-31 which another job may be using
    os.sched_setaffinity(0, range(24))
    args = sys.argv[1:]
    misses_path = os.path.join(DATA, "misses.tsv")
    if args == ["--answers"]:
        jobs, label = answers_jobs(), "answers.bin exact answers"
    elif len(args) == 4 and args[0] == "--c-texts":
        pools = [tuple(int(x) for x in line.split()) for line in open(args[2]) if line.strip()]
        jobs, label, misses_path = c_text_jobs(args[1], pools), f"{args[1]} exact answers", args[3]
    elif len(args) <= 2 and not (args and args[0].startswith("-")):
        path = args[0] if args else os.path.join(DATA, "certificates.txt.gz")
        jobs, label = certificate_jobs(path), path
        misses_path = args[1] if len(args) == 2 else misses_path
    else:
        print(USAGE, file=sys.stderr)
        return 2
    misses = load_misses(misses_path)
    total, failures, seen, gaps = 0, [], set(), 0
    with Pool(24) as workers:
        for pool, certified, bad in workers.imap(check, jobs, chunksize=8):
            total += len(certified)
            failures += bad
            seen.add(pool)
            # Require the certified targets and the claimed misses to split 100..999 exactly
            if certified & misses[pool] or certified | misses[pool] != set(TARGETS):
                gaps += 1
                print("  COVERAGE", pool, sorted(set(TARGETS) - certified - misses[pool])[:10])
    print(f"{label}: {total:,} certificates valid, {len(failures)} invalid")
    print(f"pools covered {len(seen):,} of {len(misses):,}; pools whose certificates and misses.tsv do not "
          f"partition 100..999: {gaps}")
    for f in failures[:50]:
        print("  FAIL", *f)
    return 1 if failures or gaps or len(seen) != len(misses) else 0


if __name__ == "__main__":
    sys.exit(main())
