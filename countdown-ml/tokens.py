"""
Turn rounds and answers into token sequences for the model and back
"""

import re

PAD, SEP, END = 0, 1, 36
DIGIT = 2
POOL_VALUES = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 25, 50, 75, 100]
VALUE = 12
POSITION = 26
OP = 32
OPS = "+-*/"
VOCAB = 37
PROMPT_LEN = 10
# Allow the eleven tokens of a six-number answer and its end marker
ANSWER_LEN = 12
VALUE_TOKEN = {v: VALUE + i for i, v in enumerate(POOL_VALUES)}

_token = re.compile(r"\d+|[-+*/()]")


def prompt(target, pool):
    """
    Return the tokens for a round as the target's three digits then the pool numbers then a separator
    """
    return [DIGIT + target // 100, DIGIT + target // 10 % 10, DIGIT + target % 10] + \
        [VALUE_TOKEN[v] for v in pool] + [SEP]


def answer(expr, pool):
    """
    Return the postfix tokens of an expression naming each number by its first unused position in the pool
    """
    parts = _token.findall(expr)
    at = 0
    used = [False] * len(pool)
    out = []

    def operand():
        nonlocal at
        if parts[at] == "(":
            at += 1
            binary()
            at += 1
            return
        value = int(parts[at])
        at += 1
        k = next(i for i, v in enumerate(pool) if v == value and not used[i])
        used[k] = True
        out.append(POSITION + k)

    def binary():
        nonlocal at
        operand()
        if at < len(parts) and parts[at] in OPS:
            op = parts[at]
            at += 1
            operand()
            out.append(OP + OPS.index(op))

    binary()
    return out + [END]
