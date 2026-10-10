// Work out the simplest Countdown expression that hits a target or gets closest to it

// Sort subsets with fewer values than this by insertion rather than by rank in the bitset
const RANK_MIN = 16;
const OP_ADD = 43;
const OP_SUB = 45;
const OP_MUL = 42;
const OP_DIV = 47;
// Store each entry as four words of value, operator with both masks, larger operand and smaller operand
const STRIDE = 4;

// Return the number of set bits in a 32-bit word since JavaScript has no population count
function popcount(w) {
    w -= (w >>> 1) & 0x55555555;
    w = (w & 0x33333333) + ((w >>> 2) & 0x33333333);
    return (Math.imul((w + (w >>> 4)) & 0x0f0f0f0f, 0x01010101) >>> 24);
}

// Return a copy of buffer with room for at least need words keeping its first keep words
function grow(buffer, keep, need) {
    if (need <= buffer.length) return buffer;
    let size = Math.max(buffer.length, 1024);
    while (size < need) size *= 2;
    const grown = new Uint32Array(size);
    grown.set(buffer.subarray(0, keep));
    return grown;
}

// Hold the working memory of one solve
class State {
    constructor(target, pool) {
        this.target = target;
        this.n = pool.length;
        this.full = (1 << pool.length) - 1;
        // Keep every subset's sorted values back to back in one arena
        this.arena = new Uint32Array(1024 * STRIDE);
        this.top = 0;
        this.off = new Int32Array(this.full + 1);
        this.len = new Int32Array(this.full + 1);
        // Hold the largest value each subset can make which bounds the bitset words it touches
        this.max = new Float64Array(this.full + 1);
        // Hold one bit per value seen in the subset being built
        this.seen = new Uint32Array(0);
        // Collect a subset's new values here before they are sorted into the arena
        this.tmp = new Uint32Array(1024 * STRIDE);
        // Hold the count of values below each bitset word for ranking
        this.rank = new Uint32Array(0);
        // Hold the right half's values with their reciprocals for the split being built
        this.rightValues = new Uint32Array(0);
        this.rightInv = new Float64Array(0);
    }
}

// Append every new value from pairing each left value with each right value of one split and return the new end
function emitSplit(s, left, right, out) {
    const arena = s.arena;
    const seen = s.seen;
    const tmp = s.tmp;
    const lo = s.off[left] * STRIDE;
    const nl = s.len[left];
    const ro = s.off[right] * STRIDE;
    const nr = s.len[right];
    const rv = s.rightValues;
    const ri = s.rightInv;
    // Shift each half's mask into place for both orderings of the split
    const leftLarger = (left << 8) | (right << 16);
    const rightLarger = (right << 8) | (left << 16);
    // Invert each right value once per split rather than once per pair
    for (let j = 0; j < nr; j++) {
        rv[j] = arena[ro + j * STRIDE];
        ri[j] = 1 / rv[j];
    }
    for (let i = 0; i < nl; i++) {
        const a = arena[lo + i * STRIDE];
        let j = 0;
        // Pair with right values up to a first where a is the larger and ties go left
        for (; j < nr && rv[j] <= a; j++) {
            const b = rv[j];
            // Store each result and advance only if the bitset shows it is new so duplicates cost no branch
            let v = a + b;
            let w = seen[v >>> 5];
            seen[v >>> 5] = w | (1 << (v & 31));
            tmp[out] = v; tmp[out + 1] = leftLarger | OP_ADD; tmp[out + 2] = a; tmp[out + 3] = b;
            out += (((w >>> (v & 31)) & 1) ^ 1) << 2;
            // Skip a zero result since every intermediate value must be a positive integer
            if (a !== b) {
                v = a - b;
                w = seen[v >>> 5];
                seen[v >>> 5] = w | (1 << (v & 31));
                tmp[out] = v; tmp[out + 1] = leftLarger | OP_SUB; tmp[out + 2] = a; tmp[out + 3] = b;
                out += (((w >>> (v & 31)) & 1) ^ 1) << 2;
            }
            // Skip multiplying and dividing by one as they never produce a new value
            if (b !== 1) {
                v = a * b;
                w = seen[v >>> 5];
                seen[v >>> 5] = w | (1 << (v & 31));
                tmp[out] = v; tmp[out + 1] = leftLarger | OP_MUL; tmp[out + 2] = a; tmp[out + 3] = b;
                out += (((w >>> (v & 31)) & 1) ^ 1) << 2;
                // Emit zero for an inexact division since bit 0 stays set so it is dropped
                const q = Math.round(a * ri[j]);
                v = q * b === a ? q : 0;
                w = seen[v >>> 5];
                seen[v >>> 5] = w | (1 << (v & 31));
                tmp[out] = v; tmp[out + 1] = leftLarger | OP_DIV; tmp[out + 2] = a; tmp[out + 3] = b;
                out += (((w >>> (v & 31)) & 1) ^ 1) << 2;
            }
        }
        // Pair with the remaining larger right values where a is the smaller
        const ia = 1 / a;
        for (; j < nr; j++) {
            const b = rv[j];
            let v = b + a;
            let w = seen[v >>> 5];
            seen[v >>> 5] = w | (1 << (v & 31));
            tmp[out] = v; tmp[out + 1] = rightLarger | OP_ADD; tmp[out + 2] = b; tmp[out + 3] = a;
            out += (((w >>> (v & 31)) & 1) ^ 1) << 2;
            v = b - a;
            w = seen[v >>> 5];
            seen[v >>> 5] = w | (1 << (v & 31));
            tmp[out] = v; tmp[out + 1] = rightLarger | OP_SUB; tmp[out + 2] = b; tmp[out + 3] = a;
            out += (((w >>> (v & 31)) & 1) ^ 1) << 2;
            if (a !== 1) {
                v = b * a;
                w = seen[v >>> 5];
                seen[v >>> 5] = w | (1 << (v & 31));
                tmp[out] = v; tmp[out + 1] = rightLarger | OP_MUL; tmp[out + 2] = b; tmp[out + 3] = a;
                out += (((w >>> (v & 31)) & 1) ^ 1) << 2;
                const q = Math.round(b * ia);
                v = q * a === b ? q : 0;
                w = seen[v >>> 5];
                seen[v >>> 5] = w | (1 << (v & 31));
                tmp[out] = v; tmp[out + 1] = rightLarger | OP_DIV; tmp[out + 2] = b; tmp[out + 3] = a;
                out += (((w >>> (v & 31)) & 1) ^ 1) << 2;
            }
        }
    }
    return out;
}

// Build the sorted reachable values of a subset into the arena keeping only the first way found to make each
function build(s, mask) {
    const seen = s.seen;
    let out = 0;
    // Mark zero as seen so inexact divisions never become entries
    seen[0] |= 1;
    for (let left = (mask - 1) & mask; left !== 0; left = (left - 1) & mask) {
        const right = mask ^ left;
        // Visit each split once rather than once per ordering
        if (left >= right) continue;
        // Reserve room for every pair's results plus the one slot each store may write past the end
        const bound = Math.min(4 * s.len[left] * s.len[right], s.max[mask]) + 1;
        s.tmp = grow(s.tmp, out, out + bound * STRIDE);
        out = emitSplit(s, left, right, out);
    }
    seen[0] &= ~1;

    const count = out / STRIDE;
    s.arena = grow(s.arena, s.top * STRIDE, (s.top + count) * STRIDE);
    const arena = s.arena;
    const tmp = s.tmp;
    const base = s.top * STRIDE;
    if (count < RANK_MIN) {
        // Clear only the words this subset touched and insertion sort the few values
        for (let i = 0; i < count; i++) {
            const t = i * STRIDE;
            const v = tmp[t];
            seen[v >>> 5] = 0;
            // Copy words by hand since views and copyWithin cost more than four moves
            let at = base + i * STRIDE;
            for (; at > base && arena[at - STRIDE] > v; at -= STRIDE) {
                arena[at] = arena[at - STRIDE];
                arena[at + 1] = arena[at - 3];
                arena[at + 2] = arena[at - 2];
                arena[at + 3] = arena[at - 1];
            }
            arena[at] = v;
            arena[at + 1] = tmp[t + 1];
            arena[at + 2] = tmp[t + 2];
            arena[at + 3] = tmp[t + 3];
        }
    } else {
        // Place each value at its rank in the bitset which needs no comparisons
        const words = Math.floor(s.max[mask] / 32) + 1;
        const rank = s.rank;
        let below = 0;
        for (let w = 0; w < words; w++) {
            rank[w] = below;
            // Skip counting empty words since sparse subsets have many
            const bits = seen[w];
            if (bits !== 0) below += popcount(bits);
        }
        for (let t = 0; t < out; t += STRIDE) {
            const v = tmp[t];
            const lower = seen[v >>> 5] & ((1 << (v & 31)) - 1);
            const at = base + (rank[v >>> 5] + popcount(lower)) * STRIDE;
            arena[at] = v;
            arena[at + 1] = tmp[t + 1];
            arena[at + 2] = tmp[t + 2];
            arena[at + 3] = tmp[t + 3];
        }
        seen.fill(0, 0, words);
    }
    s.off[mask] = s.top;
    s.len[mask] = count;
    s.top += count;
}

// Return the index of value among a subset's sorted values or -1 when it is absent
function lookup(s, mask, value) {
    const arena = s.arena;
    let base = s.off[mask];
    let n = s.len[mask];
    // Skip the search when the value lies outside the subset's range
    if (value < arena[base * STRIDE] || value > arena[(base + n - 1) * STRIDE]) return -1;
    // Halve the range with arithmetic so unpredictable comparisons cost no mispredicted branch
    while (n > 1) {
        const half = n >>> 1;
        base += arena[(base + half) * STRIDE] <= value ? half : 0;
        n -= half;
    }
    return arena[base * STRIDE] === value ? base : -1;
}

// Return how the target is first made from a subset as an entry without building all of its values
function findExact(s, mask) {
    const t = s.target;
    const arena = s.arena;
    for (let left = (mask - 1) & mask; left !== 0; left = (left - 1) & mask) {
        const right = mask ^ left;
        // Visit splits in the same order as building so the same origin wins
        if (left >= right) continue;
        const leftLoop = s.len[left] <= s.len[right];
        const loopMask = leftLoop ? left : right;
        const searchMask = leftLoop ? right : left;
        // Keep the lowest pair as building would since partners are tried in operator order
        let bestA = Infinity;
        let bestB = Infinity;
        let bestOp = 0;
        const start = s.off[loopMask];
        const end = start + s.len[loopMask];
        for (let i = start; i < end; i++) {
            const n = arena[i * STRIDE];
            // Try each number that combines with n to make the target in operator order
            if (leftLoop) {
                if (t > n && t - n < bestB && lookup(s, searchMask, t - n) >= 0) { bestA = n; bestB = t - n; bestOp = OP_ADD; }
                if (n > t && n - t < bestB && lookup(s, searchMask, n - t) >= 0) { bestA = n; bestB = n - t; bestOp = OP_SUB; }
                if (n + t < bestB && lookup(s, searchMask, n + t) >= 0) { bestA = n; bestB = n + t; bestOp = OP_SUB; }
                // Divide only when the quotient could be at least two since neither operand may be one
                if (n !== 1 && 2 * n <= t && t % n === 0 && t / n < bestB && lookup(s, searchMask, t / n) >= 0) { bestA = n; bestB = t / n; bestOp = OP_MUL; }
                if (n >= 2 * t && n % t === 0 && n / t < bestB && lookup(s, searchMask, n / t) >= 0) { bestA = n; bestB = n / t; bestOp = OP_DIV; }
                if (n !== 1 && n * t < bestB && lookup(s, searchMask, n * t) >= 0) { bestA = n; bestB = n * t; bestOp = OP_DIV; }
            } else {
                if (t > n && t - n < bestA && lookup(s, searchMask, t - n) >= 0) { bestA = t - n; bestB = n; bestOp = OP_ADD; }
                if (n > t && n - t < bestA && lookup(s, searchMask, n - t) >= 0) { bestA = n - t; bestB = n; bestOp = OP_SUB; }
                if (n + t < bestA && lookup(s, searchMask, n + t) >= 0) { bestA = n + t; bestB = n; bestOp = OP_SUB; }
                if (n !== 1 && 2 * n <= t && t % n === 0 && t / n < bestA && lookup(s, searchMask, t / n) >= 0) { bestA = t / n; bestB = n; bestOp = OP_MUL; }
                if (n >= 2 * t && n % t === 0 && n / t < bestA && lookup(s, searchMask, n / t) >= 0) { bestA = n / t; bestB = n; bestOp = OP_DIV; }
                if (n !== 1 && n * t < bestA && lookup(s, searchMask, n * t) >= 0) { bestA = n * t; bestB = n; bestOp = OP_DIV; }
            }
            // Take the first left value with any partner since left values ascend
            if (bestOp !== 0 && leftLoop) break;
        }
        if (bestOp !== 0) {
            return bestA >= bestB
                ? [t, bestOp | (left << 8) | (right << 16), bestA, bestB]
                : [t, bestOp | (right << 8) | (left << 16), bestB, bestA];
        }
    }
    return null;
}

// Return each subset's largest value since subtracting and dividing never exceed the larger operand
function workOutMaxima(s, pool) {
    const largest = new Float64Array(s.n + 2);
    for (let mask = 1; mask <= s.full; mask++) {
        if ((mask & (mask - 1)) === 0) {
            s.max[mask] = pool[31 - Math.clz32(mask)];
        } else {
            for (let left = (mask - 1) & mask; left !== 0; left = (left - 1) & mask) {
                const a = s.max[left];
                const b = s.max[mask ^ left];
                s.max[mask] = Math.max(s.max[mask], a * b, a + b);
            }
        }
        const size = popcount(mask);
        largest[size] = Math.max(largest[size], s.max[mask]);
    }
    return largest;
}

// Make the bitset and its ranks cover every value up to largest replacing them since building leaves the bitset clear
function reserveSeen(s, largest) {
    const words = Math.floor(largest / 32) + 1;
    if (words > s.seen.length) {
        s.seen = new Uint32Array(words);
        s.rank = new Uint32Array(words);
    }
}

// Make room for the values and reciprocals of the largest subset built so far
function reserveRights(s) {
    let biggest = 0;
    for (let mask = 1; mask <= s.full; mask++) biggest = Math.max(biggest, s.len[mask]);
    if (biggest > s.rightValues.length) {
        s.rightValues = new Uint32Array(biggest);
        s.rightInv = new Float64Array(biggest);
    }
}

// Write the expression for an entry following its origins back to the pool with brackets when asked
function render(s, value, meta, larger, smaller, bracket) {
    const op = meta & 255;
    if (op === 0) return String(value);
    const at = (mask, v) => {
        const i = lookup(s, mask, v) * STRIDE;
        return render(s, s.arena[i], s.arena[i + 1], s.arena[i + 2], s.arena[i + 3], true);
    };
    const text = `${at((meta >>> 8) & 255, larger)} ${String.fromCharCode(op)} ${at(meta >>> 16, smaller)}`;
    return bracket ? `(${text})` : text;
}

// Return the simplest expression that hits the target or gets closest to it with its value
export function solve(target, pool) {
    const s = new State(target, pool);
    const largest = workOutMaxima(s, pool);

    // Store each pool number as a one-number subset
    let best = null;
    for (let i = 0; i < s.n; i++) {
        s.arena[i * STRIDE] = pool[i];
        s.off[1 << i] = i;
        s.len[1 << i] = 1;
        if (!best && pool[i] === target) best = [pool[i], 0, 0, 0];
    }
    s.top = s.n;

    // List subsets by size then mask so the loops below need no size test
    const bySize = Array.from({ length: s.n + 1 }, () => []);
    for (let mask = 1; mask <= s.full; mask++) bySize[popcount(mask)].push(mask);

    // Work through subsets smallest first stopping at the first size that hits the target
    for (let size = 2; size <= s.n && !best; size++) {
        // Keep the lowest matching subset of this size to break ties the same way every run
        for (const mask of bySize[size]) {
            best = findExact(s, mask);
            if (best) break;
        }
        // Skip building the whole pool's values since no larger subset is made from them
        if (best || size === s.n) break;
        reserveRights(s);
        reserveSeen(s, largest[size]);
        for (const mask of bySize[size]) build(s, mask);
    }

    if (!best) {
        const arena = s.arena;
        // Rank by distance from the target then by how many numbers are used so the simplest answer wins
        let bestDistance = Infinity;
        let bestUsed = 99;
        for (let mask = 1; mask < s.full; mask++) {
            const used = popcount(mask);
            for (let i = s.off[mask]; i < s.off[mask] + s.len[mask]; i++) {
                const d = Math.abs(arena[i * STRIDE] - target);
                if (d < bestDistance || (d === bestDistance && used < bestUsed)) {
                    best = Array.from(arena.subarray(i * STRIDE, i * STRIDE + STRIDE));
                    bestDistance = d;
                    bestUsed = used;
                }
            }
        }
        // Check the whole pool's values as they are made since no larger subset is built from them
        if (s.n > 1) {
            reserveRights(s);
            let whole = null;
            let wholeDistance = Infinity;
            const consider = (v, meta, x, y) => {
                const d = Math.abs(v - target);
                if (v !== 0 && (d < wholeDistance || (d === wholeDistance && v < whole[0]))) {
                    wholeDistance = d;
                    whole = [v, meta, x, y];
                }
            };
            const full = s.full;
            for (let left = (full - 1) & full; left !== 0; left = (left - 1) & full) {
                const right = full ^ left;
                if (left >= right) continue;
                for (let i = s.off[left]; i < s.off[left] + s.len[left]; i++) {
                    const a = arena[i * STRIDE];
                    for (let j = s.off[right]; j < s.off[right] + s.len[right]; j++) {
                        const b = arena[j * STRIDE];
                        const [x, y, meta] = b <= a ? [a, b, (left << 8) | (right << 16)] : [b, a, (right << 8) | (left << 16)];
                        consider(x + y, meta | OP_ADD, x, y);
                        if (x !== y) consider(x - y, meta | OP_SUB, x, y);
                        if (y !== 1) {
                            consider(x * y, meta | OP_MUL, x, y);
                            if (x % y === 0) consider(x / y, meta | OP_DIV, x, y);
                        }
                    }
                }
            }
            // Fall back to the whole pool only when it gets strictly closer as it uses the most numbers
            if (wholeDistance < bestDistance) best = whole;
        }
    }

    // Render without outer brackets which matches stripping them from the bracketed form
    return [best[0], render(s, best[0], best[1], best[2], best[3], false)];
}
