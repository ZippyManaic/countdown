"""
Solve Countdown numbers rounds in batches as PyTorch tensor operations so a GPU can work on thousands at once
"""

import os

import torch

OPS = "+-*/"
ADD, SUB, MUL, DIV = range(4)
# Pack each value under its subset size, round and subset in one sortable key with enough bits for any cats round
VALUE_BITS = 27
VALUE_LIMIT = 1 << VALUE_BITS
VALUE_MASK = VALUE_LIMIT - 1
# Pack an origin's larger subset above its two values and its operator above that
MASK_SHIFT = 2 * VALUE_BITS
OP_SHIFT = MASK_SHIFT + 6
# Order the ways of making a value by split, larger then smaller operand and operator in one key
SPLIT_SHIFT = 2 * VALUE_BITS + 2
# Rank the closest stored value by distance above subset size above subset and value
SIZE_RANK_SHIFT = VALUE_BITS + 6
DISTANCE_SHIFT = SIZE_RANK_SHIFT + 3
# Cap the value pairs combined at once so building fits in memory
PAIR_BUDGET = 1 << 23
INF = (1 << 63) - 1
# Build the largest proper subsets only for rounds the whole pool cannot solve since searching needs one side stored
DEFER = 2
PARTNER_OPS = [ADD, SUB, SUB, MUL, DIV, DIV]


def default_device():
    """
    Return the device named by COUNTDOWN_DEVICE or the GPU when there is one
    """
    name = os.environ.get("COUNTDOWN_DEVICE")
    return torch.device(name or ("cuda" if torch.cuda.is_available() else "cpu"))


def splits(n, size, device):
    """
    Return every split of every subset of this size as subset, left, right and split number in building order
    """
    rows = []
    for mask in range(1, 1 << n):
        if mask.bit_count() != size:
            continue
        k = 0
        left = (mask - 1) & mask
        while left:
            right = mask ^ left
            # Visit each split once rather than once per ordering
            if left < right:
                rows.append((mask, left, right, k))
                k += 1
            left = (left - 1) & mask
    return torch.tensor(rows, device=device).T.contiguous()


def expand(counts):
    """
    Return the owner of every element when each owner has counts elements and each element's position within it
    """
    device = counts.device
    ends = torch.cumsum(counts, 0)
    total = int(ends[-1]) if counts.numel() else 0
    owner = torch.repeat_interleave(torch.arange(counts.numel(), device=device), counts, output_size=total)
    return owner, torch.arange(total, device=device) - (ends - counts)[owner]


def grid(rounds, count):
    """
    Return every pairing of count splits with the selected rounds as split index and round, split by split
    """
    split = torch.arange(count, device=rounds.device).repeat_interleave(rounds.numel())
    return split, rounds.repeat(count)


class Store:
    """
    Hold every value made by every built subset in one array sorted by subset size, round, subset and value
    """

    def __init__(self, count, n, device):
        self.n = n
        self.round_shift = VALUE_BITS + n
        self.size_shift = self.round_shift + max(count - 1, 1).bit_length()
        self.popcount = torch.tensor([m.bit_count() for m in range(1 << n)], device=device)
        self.key = torch.zeros(0, dtype=torch.int64, device=device)
        # Pack how each value was first made as operator, larger subset, larger value and smaller value
        self.origin = torch.zeros(0, dtype=torch.int64, device=device)
        # Find each round and subset's run of values by searching for its smallest and largest possible keys
        rounds = torch.arange(count, device=device)[:, None]
        masks = torch.arange(1 << n, device=device)
        self.lowest = self.prefix(rounds, masks)
        self.start = torch.zeros((count, 1 << n), dtype=torch.int64, device=device)
        self.len = torch.zeros_like(self.start)
        # Mark which subset sizes have their values stored for the rounds still being solved
        self.built = torch.zeros((count, n + 1), dtype=torch.bool, device=device)
        self.built[:, 1] = True
        # List each subset's splits in building order padded to the most any subset has
        table = [[] for _ in range(1 << n)]
        for mask in range(1, 1 << n):
            left = (mask - 1) & mask
            while left:
                if left < mask ^ left:
                    table[mask].append((left, mask ^ left))
                left = (left - 1) & mask
        width = max(len(row) for row in table)
        self.split_count = torch.tensor([len(row) for row in table], device=device)
        padded = torch.tensor([row + [(0, 0)] * (width - len(row)) for row in table], device=device)
        self.split_left, self.split_right = padded[..., 0].contiguous(), padded[..., 1].contiguous()

    def prefix(self, r, mask):
        return self.popcount[mask] << self.size_shift | r << self.round_shift | mask << VALUE_BITS

    def add(self, key, origin):
        self.key = torch.cat([self.key, key])
        self.origin = torch.cat([self.origin, origin])
        self.start = torch.searchsorted(self.key, self.lowest)
        self.len = torch.searchsorted(self.key, self.lowest | VALUE_MASK, right=True) - self.start

    def values(self, r, mask, i):
        return self.key[self.start[r, mask] + i] & VALUE_MASK

    def find(self, r, mask, value):
        """
        Return the position of each value in its round and subset or -1 when it is absent
        """
        query = self.prefix(r, mask) | value
        pos = torch.searchsorted(self.key, query).clamp(max=self.key.numel() - 1)
        return torch.where(self.key[pos] == query, pos, -1)


def pack_origin(op, larger_mask, larger, smaller):
    return op << OP_SHIFT | larger_mask << MASK_SHIFT | larger << VALUE_BITS | smaller


def pair_groups(store, split_rows, rounds):
    """
    Return each pair's owning split and round with its position there and every owner's operand runs and key prefix
    """
    mask, left, right, _ = split_rows
    split, r = grid(rounds, mask.numel())
    lm, rm = left[split], right[split]
    nr = store.len[r, rm]
    owner, pos = expand(store.len[r, lm] * nr)
    return owner, pos, store.start[r, lm], store.start[r, rm], nr, lm, rm, store.prefix(r, mask[split]), r


def combine(key, owner, pos, left_start, right_start, right_len, lm, rm):
    """
    Return the four results and operatorless origin of every pair with zero for an illegal result
    """
    nr = right_len[owner]
    i = pos // nr
    a = key[left_start[owner] + i] & VALUE_MASK
    b = key[right_start[owner] + pos - i * nr] & VALUE_MASK
    x, y = torch.maximum(a, b), torch.minimum(a, b)
    one = y == 1
    # Mark an illegal result as zero since no subset makes zero
    results = torch.stack([
        x + y,
        x - y,
        torch.where(one, 0, x * y),
        torch.where(one | (x % y != 0), 0, x // y),
    ], 1)
    return results, pack_origin(0, torch.where(a < b, rm[owner], lm[owner]), x, y)


@torch.compile(dynamic=True)
def build_keys(key, owner, pos, left_start, right_start, right_len, lm, rm, prefix):
    """
    Return the key of every result of every pair in building order with each pair's operatorless origin
    """
    results, origin = combine(key, owner, pos, left_start, right_start, right_len, lm, rm)
    return (prefix[owner][:, None] | results).flatten(), origin


@torch.compile(dynamic=True)
def whole_ranks(key, owner, pos, left_start, right_start, right_len, lm, rm, target):
    """
    Return every result of every pair ranked by distance from its target then value with each pair's origin
    """
    results, origin = combine(key, owner, pos, left_start, right_start, right_len, lm, rm)
    distance = (results - target[owner][:, None]).abs().clamp(max=(1 << 31) - 1)
    near = torch.where(results == 0, INF, distance << 32 | results.clamp(max=(1 << 32) - 1))
    return near.flatten(), origin


def chunks(store, split_rows, rounds):
    """
    Split the selected rounds into runs whose pairs fit the budget keeping rounds in order
    """
    _, left, right, _ = split_rows
    split, r = grid(rounds, left.numel())
    pairs = (store.len[r, left[split]] * store.len[r, right[split]]).view(left.numel(), -1).sum(0)
    ends = torch.cumsum(pairs, 0)
    cuts = torch.arange(1, int(ends[-1]) // PAIR_BUDGET + 1, device=rounds.device) * PAIR_BUDGET
    edges = sorted({0, *torch.searchsorted(ends, cuts, right=True).tolist(), rounds.numel()})
    return [rounds[a:b] for a, b in zip(edges, edges[1:]) if a < b]


def build(store, size, rounds):
    """
    Add every value the subsets of this size make in the selected rounds keeping the first way found to make each
    """
    split_rows = splits(store.n, size, rounds.device)
    keys, origins = [], []
    for part in chunks(store, split_rows, rounds):
        owner, pos, left_start, right_start, right_len, lm, rm, prefix, _ = pair_groups(store, split_rows, part)
        primary, origin = build_keys(store.key, owner, pos, left_start, right_start, right_len, lm, rm, prefix)
        # Drop illegal results before sorting since they make up about a fifth of all results
        legal = ((primary & VALUE_MASK) != 0).nonzero(as_tuple=True)[0]
        # Keep the first of each run since a stable sort leaves equal keys in building order
        primary, index = torch.sort(primary[legal], stable=True)
        keep = torch.ones_like(primary, dtype=torch.bool)
        keep[1:] = primary[1:] != primary[:-1]
        index = legal[index[keep]]
        keys.append(primary[keep])
        origins.append(origin[index >> 2] | (index & 3) << OP_SHIFT)
    store.add(torch.cat(keys), torch.cat(origins))
    store.built[rounds, size] = True


def partners(a, target):
    """
    Return every number that combines with each value to make its target in operator order with whether it is legal
    """
    m = torch.stack([target - a, a - target, a + target, target // a, a // target, a * target], 1)
    ok = torch.stack([
        target > a,
        a > target,
        torch.ones_like(a, dtype=torch.bool),
        # Divide only when the quotient could be at least two since neither operand may be one
        (a != 1) & (2 * a <= target) & (target % a == 0),
        (a >= 2 * target) & (a % target == 0),
        a != 1,
    ], 1)
    ok &= m < VALUE_LIMIT
    return m.clamp(0, VALUE_MASK), ok


def first_ways(store, r, mask, target):
    """
    Return the ordering key and origin of the first way building would make each query's target from its subset
    """
    device = r.device
    q, k = expand(store.split_count[mask])
    left, right = store.split_left[mask[q], k], store.split_right[mask[q], k]
    rq = r[q]
    # Scan the shorter stored side and look for each value's partners on the other like the C version
    big = torch.iinfo(torch.int64).max
    nl = torch.where(store.built[rq, store.popcount[left]], store.len[rq, left], big)
    nr = torch.where(store.built[rq, store.popcount[right]], store.len[rq, right], big)
    scan_left = nl <= nr
    scan, other = torch.where(scan_left, left, right), torch.where(scan_left, right, left)
    owner, i = expand(torch.minimum(nl, nr))
    re, scan, other, scan_left = rq[owner], scan[owner], other[owner], scan_left[owner]
    v = store.values(re, scan, i)
    m, ok = partners(v, target[q][owner])
    # Look partners up directly when the other side is stored and work them out from its own splits when not
    stored = store.built[re, store.popcount[other]]
    query = store.prefix(re, other)[:, None] | m
    pos = torch.searchsorted(store.key, query.flatten()).clamp(max=store.key.numel() - 1).view(m.shape)
    found = ok & (store.key[pos] == query) & stored[:, None]
    e, c = (ok & ~stored[:, None]).nonzero(as_tuple=True)
    if e.numel():
        inner, _ = first_ways(store, re[e], other[e], m[e, c])
        found[e, c] = inner != INF
    e, c = found.nonzero(as_tuple=True)
    v, w, scan_left, query_index = v[e], m[e, c], scan_left[e], q[owner[e]]
    a, b = torch.where(scan_left, v, w), torch.where(scan_left, w, v)
    split_left, split_right = left[owner[e]], right[owner[e]]
    op = torch.tensor(PARTNER_OPS, device=device)[c]
    # Order ways by split then by the left and right values which matches building since each run is sorted
    key = k[owner[e]] << SPLIT_SHIFT | a << (VALUE_BITS + 2) | b << 2 | op
    best = torch.full_like(r, INF).scatter_reduce(0, query_index, key, "amin")
    win = key == best[query_index]
    origin = torch.full_like(r, -1)
    origin[query_index[win]] = pack_origin(op, torch.where(a < b, split_right, split_left),
                                           torch.maximum(a, b), torch.minimum(a, b))[win]
    return best, origin


def find_exact(store, size, targets, rounds):
    """
    Return the rounds whose subsets of this size make the target with the subset and the first way building would find
    """
    masks = (store.popcount == size).nonzero(as_tuple=True)[0]
    r = rounds.repeat_interleave(masks.numel())
    mask = masks.repeat(rounds.numel())
    key, origin = first_ways(store, r, mask, targets[r])
    # Prefer the lowest subset in two passes since a subset and a way do not fit one key together
    hit = key != INF
    r, mask, origin = r[hit], mask[hit], origin[hit]
    best = torch.full_like(targets, INF).scatter_reduce(0, r, mask, "amin")
    win = mask == best[r]
    return r[win], mask[win], origin[win]


def closest_whole(store, targets, rounds):
    """
    Return the value closest to each target the whole pool makes taking the lower value then the first origin
    """
    split_rows = splits(store.n, store.n, rounds.device)
    out_round, out_value, out_origin = [], [], []
    for part in chunks(store, split_rows, rounds):
        owner, pos, left_start, right_start, right_len, lm, rm, _, r = pair_groups(store, split_rows, part)
        near, origin = whole_ranks(store.key, owner, pos, left_start, right_start, right_len, lm, rm, targets[r])
        r4 = r[owner].repeat_interleave(4)
        best = torch.full_like(targets, INF).scatter_reduce(0, r4, near, "amin")
        index = torch.arange(near.numel(), device=near.device)
        index = torch.where(near == best[r4], index, INF)
        first = torch.full_like(targets, INF).scatter_reduce(0, r4, index, "amin")[part]
        out_round.append(part)
        out_value.append(best[part] & ((1 << 32) - 1))
        out_origin.append(origin[first >> 2] | (first & 3) << OP_SHIFT)
    return torch.cat(out_round), torch.cat(out_value), torch.cat(out_origin)


def inorder(n):
    """
    Return the heap positions of a tree as deep as the pool allows in left to right order
    """
    width = (1 << n) - 1

    def walk(p):
        return [] if p >= width else walk(2 * p + 1) + [p] + walk(2 * p + 2)

    return walk(0)


def brackets(p, side):
    """
    Return how many bracketed subtrees a leaf at heap position p opens or closes by being their first or last leaf
    """
    count = 0
    while p and p % 2 == side:
        p = (p - 1) // 2
        # Leave the root unbracketed
        if p == 0:
            break
        count += 1
    return count


def render(node_value, node_kind, node_op):
    """
    Write every round's expression as one block of text by placing each node's characters on the device
    """
    device = node_value.device
    count, width = node_value.shape
    n = width.bit_length()
    order = torch.tensor(inorder(n), device=device)
    opens = torch.tensor([brackets(p, 1) for p in range(width)], device=device)[order]
    closes = torch.tensor([brackets(p, 0) for p in range(width)], device=device)[order]
    value, kind, op = node_value[:, order], node_kind[:, order], node_op[:, order]
    digits = torch.ones_like(value)
    for power in range(1, 10):
        digits += value >= 10 ** power
    # Treat the end of each round as a token holding just a newline
    leaf_len = opens + digits + closes
    length = torch.where(kind == 1, leaf_len, torch.where(kind == 2, 3, 0))
    length = torch.cat([length, torch.ones((count, 1), dtype=torch.int64, device=device)], 1).flatten()
    kind = torch.cat([kind, torch.full((count, 1), 3, dtype=torch.int64, device=device)], 1).flatten()
    tokens = (length > 0).nonzero(as_tuple=True)[0]
    length, kind = length[tokens], kind[tokens]
    ends = torch.cumsum(length, 0)
    starts = ends - length
    column = tokens % (width + 1)
    value = torch.cat([value, torch.zeros((count, 1), dtype=torch.int64, device=device)], 1).flatten()[tokens]
    op = torch.cat([op, torch.zeros((count, 1), dtype=torch.int64, device=device)], 1).flatten()[tokens]
    pad = torch.cat([opens, torch.zeros(1, dtype=torch.int64, device=device)])[column]
    digits = torch.cat([digits, torch.ones((count, 1), dtype=torch.int64, device=device)], 1).flatten()[tokens]
    spot = torch.arange(int(length.max()), device=device)
    # Pick each character as an open bracket, a digit or a close bracket for a leaf and an operator for a node
    d = spot - pad[:, None]
    power = (digits[:, None] - 1 - d).clamp(min=0)
    digit = (value[:, None] // torch.pow(10, power)) % 10 + ord("0")
    leaf = torch.where(d < 0, ord("("), torch.where(d < digits[:, None], digit, ord(")")))
    symbol = torch.tensor([ord(c) for c in OPS], device=device)[op][:, None]
    node = torch.where(spot == 1, symbol, ord(" "))
    char = torch.where((kind == 1)[:, None], leaf, torch.where((kind == 2)[:, None], node, ord("\n")))
    used = spot < length[:, None]
    text = torch.empty(int(ends[-1]), dtype=torch.uint8, device=device)
    text[(starts[:, None] + spot)[used]] = char[used].to(torch.uint8)
    return bytes(text.cpu().numpy()).decode("ascii").split("\n")[:-1]


def solve_batch(targets, pools, known=None):
    """
    Return every round's answer for pools of one size or None where no answer is shorter than the known one
    """
    device = targets.device
    count, n = pools.shape
    # Answer one-number pools directly since the number itself is the only expression and there is no split
    if n == 1:
        return [(v, str(v)) for v in pools[:, 0].tolist()]
    # Bound every value below the whole pool so it fits its key since a product of the numbers or two is never beaten
    bound = pools.clamp(min=2).prod(1) // pools.clamp(min=2).min(1).values
    if int(bound.max()) >= VALUE_LIMIT:
        raise ValueError("pool numbers too large to pack")
    # Keep subset masks and split numbers within the 63 bits of a ranking key
    if n > 6:
        raise ValueError("pools of more than six numbers are not supported")
    store = Store(count, n, device)
    popcount = store.popcount
    rounds = torch.arange(count, device=device)

    # Store each pool number as a one-number subset
    bits = 1 << torch.arange(n, device=device)
    single = store.prefix(rounds[:, None], bits) | pools
    store.add(single.flatten(), torch.full((count * n,), -1, device=device))

    # Record each answer's subset, value and origin with a negative origin for a pool number
    res_mask = torch.zeros_like(targets)
    res_value = torch.zeros_like(targets)
    res_origin = torch.full_like(targets, -1)
    hit = pools == targets[:, None]
    solved = hit.any(1)
    res_mask[solved] = bits[hit.int().argmax(1)][solved]
    res_value[solved] = targets[solved]

    if known is None:
        known = torch.full_like(targets, n + 1)
    proposed = torch.zeros_like(solved)

    # Work through subsets smallest first dropping each round as soon as some size makes its target
    for size in range(2, n + 1):
        # Accept a known answer once every smaller size has been searched without a hit
        accept = ~solved & (known == size)
        proposed |= accept
        solved |= accept
        active = (~solved).nonzero(as_tuple=True)[0]
        if active.numel() == 0:
            break
        r, mask, origin = find_exact(store, size, targets, active)
        res_mask[r], res_value[r], res_origin[r] = mask, targets[r], origin
        solved[r] = True
        # Build only for rounds whose next size still needs searching
        active = (~solved & (known > size + 1)).nonzero(as_tuple=True)[0]
        # Leave the largest proper subsets unbuilt until the whole pool has been searched since few rounds need them
        if size > n - DEFER or active.numel() == 0:
            continue
        build(store, size, active)

    active = (~solved).nonzero(as_tuple=True)[0]
    for size in range(max(n - DEFER + 1, 2), n):
        if active.numel():
            build(store, size, active)
    if active.numel():
        # Rank by distance from the target then by how many numbers are used then by subset and value
        key = store.key
        r = (key >> store.round_shift) & ((1 << (store.size_shift - store.round_shift)) - 1)
        value = key & VALUE_MASK
        rank = ((value - targets[r]).abs() << DISTANCE_SHIFT | (key >> store.size_shift) << SIZE_RANK_SHIFT
                | key & ((1 << store.round_shift) - 1))
        rank = torch.where(solved[r], INF, rank)
        best = torch.full_like(targets, INF).scatter_reduce(0, r, rank, "amin")[active]
        best_distance = best >> DISTANCE_SHIFT
        res_mask[active] = (best >> VALUE_BITS) & ((1 << n) - 1)
        res_value[active] = best & VALUE_MASK
        pos = store.find(active, res_mask[active], res_value[active])
        res_origin[active] = store.origin[pos]
        # Fall back to the whole pool only when it gets strictly closer as it uses the most numbers
        r, value, origin = closest_whole(store, targets, active)
        closer = (value - targets[r]).abs() < best_distance
        r, value, origin = r[closer], value[closer], origin[closer]
        res_mask[r], res_value[r], res_origin[r] = (1 << n) - 1, value, origin

    # Unfold each answer into a heap of nodes one level at a time looking up every origin it needs
    width = (1 << n) - 1
    node_mask = torch.zeros((count, width), dtype=torch.int64, device=device)
    node_value = torch.zeros_like(node_mask)
    node_origin = torch.full_like(node_mask, -1)
    # Mark each node as absent, a pool number or an operator
    node_kind = torch.zeros_like(node_mask)
    node_mask[:, 0], node_value[:, 0], node_origin[:, 0] = res_mask, res_value, res_origin
    node_kind[:, 0] = (~proposed).long()
    for depth in range(n):
        lo, hi = (1 << depth) - 1, (1 << (depth + 1)) - 1
        if depth:
            r, p = ((node_kind[:, lo:hi] > 0) & (popcount[node_mask[:, lo:hi]] > 1)).nonzero(as_tuple=True)
            p = p + lo
            mask, value = node_mask[r, p], node_value[r, p]
            pos = store.find(r, mask, value)
            origin = store.origin[pos]
            # Work out values from subsets left unbuilt for this round from their own splits
            missing = (pos < 0).nonzero(as_tuple=True)[0]
            if missing.numel():
                origin[missing] = first_ways(store, r[missing], mask[missing], value[missing])[1]
            node_origin[r, p] = origin
        r, p = (node_origin[:, lo:hi] >= 0).nonzero(as_tuple=True)
        if hi >= width or r.numel() == 0:
            break
        p = p + lo
        node_kind[r, p] = 2
        origin = node_origin[r, p]
        larger = (origin >> MASK_SHIFT) & 0x3F
        for child, mask, value in ((2 * p + 1, larger, (origin >> VALUE_BITS) & VALUE_MASK),
                                   (2 * p + 2, node_mask[r, p] ^ larger, origin & VALUE_MASK)):
            node_mask[r, child], node_value[r, child], node_kind[r, child] = mask, value, 1
    node_op = torch.where(node_origin >= 0, node_origin >> OP_SHIFT, 0)
    answers = zip(res_value.tolist(), render(node_value, node_kind, node_op), proposed.tolist())
    return [None if taken else (value, expr) for value, expr, taken in answers]


def solve_many(rounds, device=None):
    """
    Return the value and expression of the answer to every (target, pool) round in order
    """
    device = device or default_device()
    answers = [None] * len(rounds)
    # Solve pools of each size together since a batch shares its subsets
    by_size = {}
    for index, (_, pool) in enumerate(rounds):
        by_size.setdefault(len(pool), []).append(index)
    for indices in by_size.values():
        targets = torch.tensor([rounds[i][0] for i in indices], dtype=torch.int64, device=device)
        pools = torch.tensor([list(rounds[i][1]) for i in indices], dtype=torch.int64, device=device)
        for i, answer in zip(indices, solve_batch(targets, pools)):
            answers[i] = answer
    return answers


def solve(target, pool, device=None):
    """
    Return the simplest expression that hits the target or gets closest to it, with its value
    """
    return solve_many([(target, pool)], device)[0]
