// Work out the simplest Countdown expression that hits a target or gets closest to it
package countdown;

public final class Solver {

    // Sort subsets with fewer values than this by insertion rather than by rank in the bitset
    private static final int RANK_MIN = 16;
    private static final long OP_ADD = '+';
    private static final long OP_SUB = '-';
    private static final long OP_MUL = '*';
    private static final long OP_DIV = '/';
    private static final long LOW = 0xFFFF_FFFFL;

    private Solver() {
    }

    // Hold an answer with its value and expression
    public record Result(int value, String expr) {
    }

    // Hold the working memory of one solve with each entry stored as a head word and an operands word
    private static final class State {
        final long target;
        final int n;
        final int full;
        // Keep every subset's sorted values back to back in one arena
        long[] arena = new long[2 * 1024];
        int top;
        final int[] off;
        final int[] len;
        // Hold the largest value each subset can make which bounds the bitset words it touches
        final long[] max;
        // Hold one bit per value seen in the subset being built
        long[] seen = new long[0];
        // Collect a subset's new values here before they are sorted into the arena
        long[] tmp = new long[2 * 1024];
        // Hold the count of values below each bitset word for ranking
        int[] rank = new int[0];
        // Hold the right half's values with their reciprocals for the split being built
        long[] rightValues = new long[0];
        double[] rightInv = new double[0];

        State(int target, int n) {
            this.target = target;
            this.n = n;
            this.full = (1 << n) - 1;
            this.off = new int[full + 1];
            this.len = new int[full + 1];
            this.max = new long[full + 1];
        }
    }

    // Return the operator and masks of an entry shifted above its value
    private static long template(long op, int largerMask, int smallerMask) {
        return (op | (long) largerMask << 8 | (long) smallerMask << 16) << 32;
    }

    // Return a copy of words with room for at least need words keeping its first keep words
    private static long[] grow(long[] words, int keep, int need) {
        if (need <= words.length) {
            return words;
        }
        int size = Math.max(words.length, 2048);
        while (size < need) {
            size *= 2;
        }
        long[] grown = new long[size];
        System.arraycopy(words, 0, grown, 0, keep);
        return grown;
    }

    // Append every new value from pairing each left value with each right value of one split and return the new end
    private static int emitSplit(State s, int left, int right, int out) {
        final long[] arena = s.arena;
        final long[] seen = s.seen;
        final long[] tmp = s.tmp;
        final long[] rv = s.rightValues;
        final double[] ri = s.rightInv;
        final int nr = s.len[right];
        final long tlAdd = template(OP_ADD, left, right);
        final long tlSub = template(OP_SUB, left, right);
        final long tlMul = template(OP_MUL, left, right);
        final long tlDiv = template(OP_DIV, left, right);
        final long trAdd = template(OP_ADD, right, left);
        final long trSub = template(OP_SUB, right, left);
        final long trMul = template(OP_MUL, right, left);
        final long trDiv = template(OP_DIV, right, left);
        // Invert each right value once per split rather than once per pair
        for (int j = 0; j < nr; j++) {
            rv[j] = arena[2 * (s.off[right] + j)] & LOW;
            ri[j] = 1.0 / rv[j];
        }
        final int start = s.off[left];
        final int end = start + s.len[left];
        for (int i = start; i < end; i++) {
            final long a = arena[2 * i] & LOW;
            int j = 0;
            // Pair with right values up to a first where a is the larger and ties go left
            for (; j < nr && rv[j] <= a; j++) {
                final long b = rv[j];
                final long operands = a | b << 32;
                out = emit(seen, tmp, out, a + b, tlAdd, operands);
                // Skip a zero result since every intermediate value must be a positive integer
                if (a != b) {
                    out = emit(seen, tmp, out, a - b, tlSub, operands);
                }
                // Skip multiplying and dividing by one as they never produce a new value
                if (b != 1) {
                    out = emit(seen, tmp, out, a * b, tlMul, operands);
                    out = emit(seen, tmp, out, exact(a, b, ri[j]), tlDiv, operands);
                }
            }
            // Pair with the remaining larger right values where a is the smaller
            final double ia = 1.0 / a;
            for (; j < nr; j++) {
                final long b = rv[j];
                final long operands = b | a << 32;
                out = emit(seen, tmp, out, b + a, trAdd, operands);
                out = emit(seen, tmp, out, b - a, trSub, operands);
                if (a != 1) {
                    out = emit(seen, tmp, out, b * a, trMul, operands);
                    out = emit(seen, tmp, out, exact(b, a, ia), trDiv, operands);
                }
            }
        }
        return out;
    }

    // Store a value and return the next slot which moves on only if the bitset shows the value is new
    private static int emit(long[] seen, long[] tmp, int out, long v, long tmpl, long operands) {
        final int word = (int) (v >>> 6);
        final long w = seen[word];
        seen[word] = w | 1L << v;
        tmp[out] = tmpl | v;
        tmp[out + 1] = operands;
        return out + (int) ((~w >>> v & 1) << 1);
    }

    // Return x divided by y when the division is exact and zero otherwise using the reciprocal of y
    private static long exact(long x, long y, double inv) {
        final long q = (long) (x * inv + 0.5);
        // Mask with arithmetic so the comparison costs no mispredicted branch
        return q & -(q * y == x ? 1L : 0L);
    }

    // Build the sorted reachable values of a subset into the arena keeping only the first way found to make each
    private static void build(State s, int mask) {
        final long[] seen = s.seen;
        int out = 0;
        // Mark zero as seen so inexact divisions never become entries
        seen[0] |= 1;
        for (int left = (mask - 1) & mask; left != 0; left = (left - 1) & mask) {
            final int right = mask ^ left;
            // Visit each split once rather than once per ordering
            if (left >= right) {
                continue;
            }
            // Reserve room for every pair's results plus the one slot each store may write past the end
            final long bound = Math.min(4L * s.len[left] * s.len[right], s.max[mask]) + 1;
            s.tmp = grow(s.tmp, out, out + (int) (2 * bound));
            out = emitSplit(s, left, right, out);
        }
        seen[0] &= ~1L;

        final int count = out / 2;
        s.arena = grow(s.arena, 2 * s.top, 2 * (s.top + count));
        final long[] arena = s.arena;
        final long[] tmp = s.tmp;
        final int base = 2 * s.top;
        if (count < RANK_MIN) {
            // Clear only the words this subset touched and insertion sort the few values
            for (int i = 0; i < count; i++) {
                final long head = tmp[2 * i];
                final long operands = tmp[2 * i + 1];
                final long v = head & LOW;
                seen[(int) (v >>> 6)] = 0;
                int at = base + 2 * i;
                for (; at > base && (arena[at - 2] & LOW) > v; at -= 2) {
                    arena[at] = arena[at - 2];
                    arena[at + 1] = arena[at - 1];
                }
                arena[at] = head;
                arena[at + 1] = operands;
            }
        } else {
            // Place each value at its rank in the bitset which needs no comparisons
            final int words = (int) (s.max[mask] >>> 6) + 1;
            final int[] rank = s.rank;
            int below = 0;
            for (int w = 0; w < words; w++) {
                rank[w] = below;
                below += Long.bitCount(seen[w]);
            }
            for (int t = 0; t < out; t += 2) {
                final long v = tmp[t] & LOW;
                final int w = (int) (v >>> 6);
                final long lower = seen[w] & ((1L << v) - 1);
                final int at = base + 2 * (rank[w] + Long.bitCount(lower));
                arena[at] = tmp[t];
                arena[at + 1] = tmp[t + 1];
            }
            java.util.Arrays.fill(seen, 0, words, 0);
        }
        s.off[mask] = s.top;
        s.len[mask] = count;
        s.top += count;
    }

    // Return the arena index of value in a subset or -1 when it is absent
    private static int lookup(State s, int mask, long value) {
        final long[] arena = s.arena;
        int base = s.off[mask];
        int n = s.len[mask];
        // Skip the search when the value lies outside the subset's range
        if (n == 0 || value < (arena[2 * base] & LOW) || value > (arena[2 * (base + n - 1)] & LOW)) {
            return -1;
        }
        // Halve the range with a conditional move so unpredictable comparisons cost no mispredicted branch
        while (n > 1) {
            final int half = n >>> 1;
            base += (arena[2 * (base + half)] & LOW) <= value ? half : 0;
            n -= half;
        }
        return (arena[2 * base] & LOW) == value ? base : -1;
    }

    // Return how the target is first made from a subset as a head and operands pair without building all of its values
    private static long[] findExact(State s, int mask) {
        final long t = s.target;
        final long[] arena = s.arena;
        for (int left = (mask - 1) & mask; left != 0; left = (left - 1) & mask) {
            final int right = mask ^ left;
            // Visit splits in the same order as building so the same origin wins
            if (left >= right) {
                continue;
            }
            final boolean leftLoop = s.len[left] <= s.len[right];
            final int loopMask = leftLoop ? left : right;
            final int searchMask = leftLoop ? right : left;
            // Keep the lowest pair as building would since partners are tried in operator order
            long bestA = Long.MAX_VALUE;
            long bestB = Long.MAX_VALUE;
            long bestOp = 0;
            final int end = s.off[loopMask] + s.len[loopMask];
            for (int i = s.off[loopMask]; i < end; i++) {
                final long n = arena[2 * i] & LOW;
                // Try each number that combines with n to make the target in operator order
                if (leftLoop) {
                    if (t > n && t - n < bestB && lookup(s, searchMask, t - n) >= 0) {
                        bestA = n; bestB = t - n; bestOp = OP_ADD;
                    }
                    if (n > t && n - t < bestB && lookup(s, searchMask, n - t) >= 0) {
                        bestA = n; bestB = n - t; bestOp = OP_SUB;
                    }
                    if (n + t < bestB && lookup(s, searchMask, n + t) >= 0) {
                        bestA = n; bestB = n + t; bestOp = OP_SUB;
                    }
                    // Divide only when the quotient could be at least two since neither operand may be one
                    if (n != 1 && 2 * n <= t && t % n == 0 && t / n < bestB && lookup(s, searchMask, t / n) >= 0) {
                        bestA = n; bestB = t / n; bestOp = OP_MUL;
                    }
                    if (n >= 2 * t && n % t == 0 && n / t < bestB && lookup(s, searchMask, n / t) >= 0) {
                        bestA = n; bestB = n / t; bestOp = OP_DIV;
                    }
                    if (n != 1 && n * t < bestB && lookup(s, searchMask, n * t) >= 0) {
                        bestA = n; bestB = n * t; bestOp = OP_DIV;
                    }
                } else {
                    if (t > n && t - n < bestA && lookup(s, searchMask, t - n) >= 0) {
                        bestA = t - n; bestB = n; bestOp = OP_ADD;
                    }
                    if (n > t && n - t < bestA && lookup(s, searchMask, n - t) >= 0) {
                        bestA = n - t; bestB = n; bestOp = OP_SUB;
                    }
                    if (n + t < bestA && lookup(s, searchMask, n + t) >= 0) {
                        bestA = n + t; bestB = n; bestOp = OP_SUB;
                    }
                    if (n != 1 && 2 * n <= t && t % n == 0 && t / n < bestA && lookup(s, searchMask, t / n) >= 0) {
                        bestA = t / n; bestB = n; bestOp = OP_MUL;
                    }
                    if (n >= 2 * t && n % t == 0 && n / t < bestA && lookup(s, searchMask, n / t) >= 0) {
                        bestA = n / t; bestB = n; bestOp = OP_DIV;
                    }
                    if (n != 1 && n * t < bestA && lookup(s, searchMask, n * t) >= 0) {
                        bestA = n * t; bestB = n; bestOp = OP_DIV;
                    }
                }
                // Take the first left value with any partner since left values ascend
                if (bestOp != 0 && leftLoop) {
                    break;
                }
            }
            if (bestOp != 0) {
                return bestA >= bestB
                        ? new long[] {template(bestOp, left, right) | t, bestA | bestB << 32}
                        : new long[] {template(bestOp, right, left) | t, bestB | bestA << 32};
            }
        }
        return null;
    }

    // Write the expression for an entry following its origins back to the pool with brackets when asked
    private static void render(State s, long head, long operands, boolean bracket, StringBuilder out) {
        final long op = head >>> 32 & 255;
        if (op == 0) {
            out.append(head & LOW);
            return;
        }
        final int larger = lookup(s, (int) (head >>> 40 & 255), operands & LOW);
        final int smaller = lookup(s, (int) (head >>> 48 & 255), operands >>> 32);
        if (bracket) {
            out.append('(');
        }
        render(s, s.arena[2 * larger], s.arena[2 * larger + 1], true, out);
        out.append(' ').append((char) op).append(' ');
        render(s, s.arena[2 * smaller], s.arena[2 * smaller + 1], true, out);
        if (bracket) {
            out.append(')');
        }
    }

    // Return the simplest expression that hits the target or gets closest to it with its value
    public static Result solve(int target, int[] pool) {
        final State s = new State(target, pool.length);
        final int n = pool.length;

        // Work out each subset's largest value since subtracting and dividing never exceed the larger operand
        final long[] largest = new long[n + 2];
        for (int mask = 1; mask <= s.full; mask++) {
            if ((mask & (mask - 1)) == 0) {
                s.max[mask] = pool[Integer.numberOfTrailingZeros(mask)];
            } else {
                for (int left = (mask - 1) & mask; left != 0; left = (left - 1) & mask) {
                    final long a = s.max[left];
                    final long b = s.max[mask ^ left];
                    s.max[mask] = Math.max(s.max[mask], Math.max(a * b, a + b));
                }
            }
            // Track the largest value of each size so the bitset only grows when bigger subsets are built
            final int size = Integer.bitCount(mask);
            largest[size] = Math.max(largest[size], s.max[mask]);
        }

        // Store each pool number as a one-number subset
        long[] best = null;
        for (int i = 0; i < n; i++) {
            s.arena[2 * i] = pool[i];
            s.off[1 << i] = i;
            s.len[1 << i] = 1;
            if (best == null && pool[i] == target) {
                best = new long[] {pool[i], 0};
            }
        }
        s.top = n;

        // Work through subsets smallest first stopping at the first size that hits the target
        for (int size = 2; size <= n && best == null; size++) {
            // Keep the lowest matching subset of this size to break ties the same way every run
            for (int mask = 1; mask <= s.full && best == null; mask++) {
                if (Integer.bitCount(mask) == size) {
                    best = findExact(s, mask);
                }
            }
            // Skip building the whole pool's values since no larger subset is made from them
            if (best != null || size == n) {
                break;
            }
            int biggest = 0;
            for (int mask = 1; mask <= s.full; mask++) {
                biggest = Math.max(biggest, s.len[mask]);
            }
            if (biggest > s.rightValues.length) {
                s.rightValues = new long[biggest];
                s.rightInv = new double[biggest];
            }
            final int words = (int) (largest[size] >>> 6) + 1;
            // Replace rather than copy since building leaves the bitset clear
            if (words > s.seen.length) {
                s.seen = new long[words];
                s.rank = new int[words];
            }
            for (int mask = 1; mask <= s.full; mask++) {
                if (Integer.bitCount(mask) == size) {
                    build(s, mask);
                }
            }
        }

        if (best == null) {
            best = closest(s);
        }

        // Render without outer brackets which matches stripping them from the bracketed form
        final StringBuilder expr = new StringBuilder();
        render(s, best[0], best[1], false, expr);
        return new Result((int) (best[0] & LOW), expr.toString());
    }

    // Return the closest value as a head and operands pair when no subset can make the target
    private static long[] closest(State s) {
        final long[] arena = s.arena;
        final long t = s.target;
        long[] best = null;
        // Rank by distance from the target then by how many numbers are used so the simplest answer wins
        long bestDistance = Long.MAX_VALUE;
        int bestUsed = 99;
        // Include a one-number pool here since the whole-pool pass below needs at least two numbers
        final int last = s.n > 1 ? s.full - 1 : s.full;
        for (int mask = 1; mask <= last; mask++) {
            final int used = Integer.bitCount(mask);
            for (int i = s.off[mask]; i < s.off[mask] + s.len[mask]; i++) {
                final long d = Math.abs((arena[2 * i] & LOW) - t);
                if (d < bestDistance || (d == bestDistance && used < bestUsed)) {
                    best = new long[] {arena[2 * i], arena[2 * i + 1]};
                    bestDistance = d;
                    bestUsed = used;
                }
            }
        }
        if (s.n == 1) {
            return best;
        }
        // Check the whole pool's values as they are made since no larger subset is built from them
        long[] whole = null;
        long wholeDistance = Long.MAX_VALUE;
        final int full = s.full;
        for (int left = (full - 1) & full; left != 0; left = (left - 1) & full) {
            final int right = full ^ left;
            if (left >= right) {
                continue;
            }
            for (int i = s.off[left]; i < s.off[left] + s.len[left]; i++) {
                for (int j = s.off[right]; j < s.off[right] + s.len[right]; j++) {
                    final long a = arena[2 * i] & LOW;
                    final long b = arena[2 * j] & LOW;
                    final long x = Math.max(a, b);
                    final long y = Math.min(a, b);
                    final int lm = b <= a ? left : right;
                    final int sm = b <= a ? right : left;
                    final long operands = x | y << 32;
                    final long[] results = {x + y, x != y ? x - y : 0, y != 1 ? x * y : 0, y != 1 && x % y == 0 ? x / y : 0};
                    final long[] ops = {OP_ADD, OP_SUB, OP_MUL, OP_DIV};
                    for (int k = 0; k < 4; k++) {
                        final long v = results[k];
                        final long d = Math.abs(v - t);
                        // Prefer the lower value on equal distance to break ties the same way every run
                        if (v != 0 && (d < wholeDistance || (d == wholeDistance && v < (whole[0] & LOW)))) {
                            whole = new long[] {template(ops[k], lm, sm) | v, operands};
                            wholeDistance = d;
                        }
                    }
                }
            }
        }
        // Fall back to the whole pool only when it gets strictly closer as it uses the most numbers
        return wholeDistance < bestDistance ? whole : best;
    }
}
