"""
Solve Countdown rounds by letting a trained transformer propose answers and the PyTorch solver prove none is shorter
"""

import importlib.util
import os
import sys

import torch

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from model import Model  # noqa: E402
from tokens import ANSWER_LEN, DIGIT, END, OP, PAD, POOL_VALUES, POSITION, PROMPT_LEN, SEP, VALUE, VOCAB  # noqa: E402

MODEL = os.environ.get("COUNTDOWN_MODEL", os.path.join(HERE, "model.pt"))
# Decode greedily by default since wider beams find more answers but cost more than the search they save
BEAMS = int(os.environ.get("COUNTDOWN_BEAMS", 1))
# Cap the sequences decoded at once so the cached keys and values fit in GPU memory
SEQUENCES = 1 << 14

# Load the PyTorch solver by path since it shares this module's name
_spec = importlib.util.spec_from_file_location("exact", os.path.join(HERE, "..", "countdown-torch", "solver.py"))
exact = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(exact)

_models = {}
default_device = exact.default_device


def load(device):
    """
    Return the trained model on the device loading it the first time it is needed
    """
    if device not in _models:
        saved = torch.load(MODEL, map_location=device)
        model = Model(saved["width"], saved["depth"], max(saved["width"] // 64, 1)).to(device)
        model.load_state_dict(saved["state"])
        _models[device] = model.eval()
    return _models[device]


def apply(op, x, y):
    """
    Return the result of each operator on larger values x and smaller values y
    """
    return torch.where(op == 0, x + y, torch.where(op == 1, x - y, torch.where(op == 2, x * y,
                                                                                   x // y.clamp(min=1))))


@torch.no_grad()
def propose(model, targets, pools, beams):
    """
    Return each round's best legal answer in postfix tokens from a beam search with its number count or zero for none
    """
    device = targets.device
    count, n = pools.shape
    total = count * beams
    token_of = torch.zeros(101, dtype=torch.int64, device=device)
    token_of[torch.tensor(POOL_VALUES, device=device)] = torch.arange(VALUE, VALUE + len(POOL_VALUES), device=device)
    prompt = torch.cat([torch.stack([targets // 100, targets // 10 % 10, targets % 10], 1) + DIGIT,
                        token_of[pools], torch.full((count, 1), SEP, device=device)], 1)
    caches = [{} for _ in model.blocks]
    with torch.autocast(device.type, dtype=torch.bfloat16, enabled=device.type == "cuda"):
        logits = model(prompt.repeat_interleave(beams, 0), 0, caches)[:, -1]
    pool = pools.repeat_interleave(beams, 0)
    target = targets.repeat_interleave(beams)
    stack = torch.zeros((total, n), dtype=torch.int64, device=device)
    depth = torch.zeros(total, dtype=torch.int64, device=device)
    used = torch.zeros_like(depth)
    done = torch.zeros(total, dtype=torch.bool, device=device)
    history = torch.full((total, ANSWER_LEN), PAD, dtype=torch.int64, device=device)
    score = torch.zeros(count, beams, device=device)
    # Start from one beam per round since every beam begins identical
    score[:, 1:] = -torch.inf
    score = score.flatten()
    rows = torch.arange(total, device=device)
    bits = 1 << torch.arange(n, device=device)
    for step in range(ANSWER_LEN):
        logp = torch.log_softmax(logits.float(), -1)
        # Allow only tokens that keep the postfix legal under Countdown rules
        allowed = torch.zeros((total, VOCAB), dtype=torch.bool, device=device)
        allowed[:, POSITION:POSITION + n] = (used[:, None] & bits) == 0
        top = stack[rows, (depth - 1).clamp(min=0)]
        below = stack[rows, (depth - 2).clamp(min=0)]
        x, y = torch.maximum(top, below), torch.minimum(top, below)
        one = y == 1
        legal = torch.stack([torch.ones_like(one), x != y, ~one, ~one & (x % y.clamp(min=1) == 0)], 1)
        allowed[:, OP:OP + 4] = legal & (depth >= 2)[:, None]
        allowed[:, END] = depth == 1
        allowed &= ~done[:, None]
        allowed[:, PAD] = done
        logp = torch.where(allowed, logp, -torch.inf)
        logp[:, PAD] = torch.where(done, 0.0, -torch.inf)
        candidates = (score[:, None] + logp).view(count, beams * VOCAB)
        score, index = candidates.topk(beams, 1)
        parent = (index // VOCAB + torch.arange(count, device=device)[:, None] * beams).flatten()
        token = (index % VOCAB).flatten()
        score = score.flatten()
        stack, depth, used, done, history = stack[parent], depth[parent], used[parent], done[parent], history[parent]
        # Reorder cached keys and values only when beams can swap places
        if beams > 1:
            for cache in caches:
                cache["k"], cache["v"] = cache["k"][parent], cache["v"][parent]
        history[:, step] = token
        leaf = (token >= POSITION) & (token < POSITION + n)
        position = (token - POSITION).clamp(0, n - 1)
        is_op = (token >= OP) & (token < OP + 4)
        top = stack[rows, (depth - 1).clamp(min=0)]
        below = stack[rows, (depth - 2).clamp(min=0)]
        result = apply(token - OP, torch.maximum(top, below), torch.minimum(top, below))
        slot = torch.where(leaf, depth, (depth - 2).clamp(min=0))
        stack[rows, slot] = torch.where(leaf, pool[rows, position], torch.where(is_op, result, stack[rows, slot]))
        depth = depth + leaf.long() - is_op.long()
        used = used | torch.where(leaf, 1 << position, 0)
        done = done | (token == END)
        if bool(done.all()):
            break
        with torch.autocast(device.type, dtype=torch.bfloat16, enabled=device.type == "cuda"):
            logits = model(torch.where(done, PAD, token)[:, None], PROMPT_LEN + step, caches)[:, -1]
    # Take the beam hitting the target with the fewest numbers then the highest score
    numbers = sum((used >> k) & 1 for k in range(n))
    hit = done & (stack[:, 0] == target) & (score > -torch.inf)
    rank = torch.where(hit, numbers * beams + torch.arange(total, device=device) % beams, 1 << 30).view(count, beams)
    best = rank.argmin(1) + torch.arange(count, device=device) * beams
    found = hit[best]
    return history[best], torch.where(found, numbers[best], 0)


def unfold(tokens, pools):
    """
    Return the heap of node values, kinds and operators for each postfix answer with the larger operand first
    """
    device = tokens.device
    count, n = pools.shape
    width = (1 << n) - 1
    rows = torch.arange(count, device=device)
    value = torch.zeros((count, ANSWER_LEN), dtype=torch.int64, device=device)
    larger = torch.full_like(value, -1)
    smaller = torch.full_like(value, -1)
    stack = torch.zeros((count, n), dtype=torch.int64, device=device)
    depth = torch.zeros(count, dtype=torch.int64, device=device)
    for t in range(ANSWER_LEN):
        token = tokens[:, t]
        leaf = (token >= POSITION) & (token < POSITION + n)
        is_op = (token >= OP) & (token < OP + 4)
        a = stack[rows, (depth - 2).clamp(min=0)]
        b = stack[rows, (depth - 1).clamp(min=0)]
        # Put the first operand first when both are equal
        first = value[rows, a] >= value[rows, b]
        big, small = torch.where(first, a, b), torch.where(first, b, a)
        value[:, t] = torch.where(leaf, pools[rows, (token - POSITION).clamp(0, n - 1)],
                                  apply(token - OP, value[rows, big], value[rows, small]))
        larger[:, t] = torch.where(is_op, big, -1)
        smaller[:, t] = torch.where(is_op, small, -1)
        slot = torch.where(leaf, depth, (depth - 2).clamp(min=0))
        stack[rows, slot] = torch.where(leaf | is_op, t, stack[rows, slot])
        depth = depth + leaf.long() - is_op.long()
    heap = torch.full_like(value, -1)
    heap[rows, stack[:, 0]] = 0
    # Place children after parents by walking backwards since postfix puts each operator after its operands
    for t in reversed(range(ANSWER_LEN)):
        here = heap[:, t]
        inner = (larger[:, t] >= 0) & (here >= 0)
        for child, offset in ((larger[:, t], 1), (smaller[:, t], 2)):
            heap[rows, child.clamp(min=0)] = torch.where(inner, 2 * here + offset, heap[rows, child.clamp(min=0)])
    node_value = torch.zeros((count, width + 1), dtype=torch.int64, device=device)
    node_kind = torch.zeros_like(node_value)
    node_op = torch.zeros_like(node_value)
    # Send tokens without a place to a spare column that is dropped
    place = torch.where(heap >= 0, heap, width)
    is_op = (tokens >= OP) & (tokens < OP + 4)
    node_value.scatter_(1, place, value)
    node_kind.scatter_(1, place, torch.where(heap >= 0, torch.where(is_op, 2, 1), 0))
    node_op.scatter_(1, place, torch.where(is_op, tokens - OP, 0))
    return node_value[:, :width], node_kind[:, :width], node_op[:, :width]


def solve_many(rounds, device=None):
    """
    Return the value and expression of the answer to every (target, pool) round in order
    """
    device = device or exact.default_device()
    model = load(device)
    answers = [None] * len(rounds)
    by_size = {}
    for index, (_, pool) in enumerate(rounds):
        by_size.setdefault(len(pool), []).append(index)
    for indices in by_size.values():
        targets = torch.tensor([rounds[i][0] for i in indices], dtype=torch.int64, device=device)
        pools = torch.tensor([list(rounds[i][1]) for i in indices], dtype=torch.int64, device=device)
        n = pools.shape[1]
        if n == 6:
            step = max(SEQUENCES // BEAMS, 1)
            parts = [propose(model, targets[k:k + step], pools[k:k + step], BEAMS)
                     for k in range(0, len(indices), step)]
            tokens, numbers = torch.cat([p[0] for p in parts]), torch.cat([p[1] for p in parts])
        else:
            tokens, numbers = None, torch.zeros_like(targets)
        known = torch.where(numbers > 0, numbers, n + 1)
        solved = exact.solve_batch(targets, pools, known)
        if tokens is not None and any(a is None for a in solved):
            texts = exact.render(*unfold(tokens, pools))
            values = targets.tolist()
            solved = [(values[k], texts[k]) if a is None else a for k, a in enumerate(solved)]
        for i, answer in zip(indices, solved):
            answers[i] = answer
    return answers


def solve(target, pool, device=None):
    """
    Return the simplest expression that hits the target or gets closest to it, with its value
    """
    return solve_many([(target, pool)], device)[0]
