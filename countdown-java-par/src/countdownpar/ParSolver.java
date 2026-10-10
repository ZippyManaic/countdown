// Work out the simplest Countdown expression for one round with several threads sharing each level of the search
package countdownpar;

import java.util.concurrent.ForkJoinPool;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.locks.LockSupport;
import java.util.stream.IntStream;

public final class ParSolver {

    // Sort subsets with fewer values than this by insertion rather than by rank in the bitset
    private static final int RANK_MIN = 16;
    private static final long OP_ADD = '+';
    private static final long OP_SUB = '-';
    private static final long OP_MUL = '*';
    private static final long OP_DIV = '/';
    private static final long LOW = 0xFFFF_FFFFL;
    private static final long NONE = Long.MAX_VALUE;

    // Read the thread count once since the worker pool outlives every solve and default to no more than the cores allowed
    static final int THREADS = Math.max(1, setting("COUNTDOWN_THREADS",
            Math.min(8, Runtime.getRuntime().availableProcessors())));
    // Share a build level only above this many pairs since smaller levels finish before workers could help
    static final long BUILD_MIN = setting("COUNTDOWN_BUILD_MIN", 0);
    // Share the whole pool's exact search only above this many scanned values for the same reason
    static final long FIND_MIN = setting("COUNTDOWN_FIND_MIN", 0);
    // Share the whole-pool pass only above this many pairs
    static final long WHOLE_MIN = setting("COUNTDOWN_WHOLE_MIN", 2000);
    private static final Runner RUNNER = runner();

    private ParSolver() {
    }

    // Hold an answer with its value and expression
    public record Result(int value, String expr) {
    }

    // Read a whole-number setting from the environment falling back to a default
    private static int setting(String name, int fallback) {
        final String text = System.getenv(name);
        return text == null || text.isBlank() ? fallback : Integer.parseInt(text.trim());
    }

    // Do one item of a shared job as the worker with the given index
    interface Work {
        void run(int item, int worker);
    }

    // Run every item of a job across the workers and return once all have finished
    interface Runner {
        void run(Work work, int items);
    }

    // Pick the way jobs reach the workers with spinning platform threads as the default
    private static Runner runner() {
        if (THREADS == 1) {
            return (work, items) -> {
                for (int i = 0; i < items; i++) {
                    work.run(i, 0);
                }
            };
        }
        final String kind = System.getenv("COUNTDOWN_POOL");
        if ("fj".equals(kind)) {
            return new ForkJoinRunner();
        }
        if ("virtual".equals(kind)) {
            return new VirtualRunner();
        }
        return new SpinPool();
    }

    // Hold one job's items with counters for claiming and finishing them
    static final class Job {
        final Work work;
        final int items;
        final AtomicInteger next = new AtomicInteger();
        final AtomicInteger done = new AtomicInteger();
        volatile Throwable failure;

        Job(Work work, int items) {
            this.work = work;
            this.items = items;
        }

        // Claim and run items until none are left counting each one finished even when it fails
        void drain(int worker) {
            for (int i; (i = next.getAndIncrement()) < items;) {
                try {
                    work.run(i, worker);
                } catch (Throwable t) {
                    failure = t;
                }
                done.incrementAndGet();
            }
        }

        // Wait for every claimed item to finish and pass on any failure
        void await() {
            while (done.get() < items) {
                Thread.onSpinWait();
            }
            if (failure != null) {
                throw new IllegalStateException("worker failed", failure);
            }
        }
    }

    // Keep platform threads spinning on the latest job so a new level reaches them within a fraction of a microsecond
    static final class SpinPool implements Runner {
        // Spin this many times before parking so an idle program stops using the cores
        private static final int SPIN = 1 << 18;
        private final Worker[] workers = new Worker[THREADS - 1];
        private volatile Job current;

        SpinPool() {
            for (int k = 0; k < workers.length; k++) {
                workers[k] = new Worker(k + 1);
                workers[k].start();
            }
        }

        @Override
        public void run(Work work, int items) {
            final Job job = new Job(work, items);
            current = job;
            for (Worker w : workers) {
                if (w.sleeping) {
                    LockSupport.unpark(w);
                }
            }
            job.drain(0);
            job.await();
        }

        // Wait for each new job and help drain it
        final class Worker extends Thread {
            private final int index;
            volatile boolean sleeping;

            Worker(int index) {
                super("countdown-worker-" + index);
                this.index = index;
                // Let the program exit while workers wait
                setDaemon(true);
            }

            @Override
            public void run() {
                Job last = null;
                int spins = 0;
                while (true) {
                    final Job job = current;
                    if (job != last) {
                        last = job;
                        spins = 0;
                        job.drain(index);
                    } else if (++spins < SPIN) {
                        Thread.onSpinWait();
                    } else {
                        // Publish the intention to sleep before checking again so a submitter cannot miss it
                        sleeping = true;
                        if (current == last) {
                            LockSupport.park(this);
                        }
                        sleeping = false;
                        spins = 0;
                    }
                }
            }
        }
    }

    // Run each job as a parallel stream inside a dedicated fork-join pool
    static final class ForkJoinRunner implements Runner {
        private final ForkJoinPool pool = new ForkJoinPool(THREADS);

        // Number each pool thread once since pool indices can run past the thread count
        private final AtomicInteger issued = new AtomicInteger();
        private final ThreadLocal<Integer> index = ThreadLocal.withInitial(issued::incrementAndGet);

        @Override
        public void run(Work work, int items) {
            pool.submit(() -> IntStream.range(0, items).parallel().forEach(i -> work.run(i, index.get()))).join();
        }
    }

    // Start fresh virtual threads for each job which then drain it alongside the caller
    static final class VirtualRunner implements Runner {
        @Override
        public void run(Work work, int items) {
            final Job job = new Job(work, items);
            final int helpers = Math.min(THREADS - 1, items - 1);
            final Thread[] threads = new Thread[Math.max(helpers, 0)];
            for (int k = 0; k < threads.length; k++) {
                final int worker = k + 1;
                threads[k] = Thread.ofVirtual().start(() -> job.drain(worker));
            }
            job.drain(0);
            for (Thread t : threads) {
                try {
                    t.join();
                } catch (InterruptedException e) {
                    Thread.currentThread().interrupt();
                }
            }
            job.await();
        }
    }

    // Hold one worker's buffers for building subsets which every solve allocates afresh
    static final class Scratch {
        // Hold one bit per value seen in the subset being built
        long[] seen = new long[0];
        // Hold the count of values below each bitset word for ranking
        int[] rank = new int[0];
        // Collect a subset's new values here before they are sorted
        long[] tmp = new long[2 * 1024];
        // Hold the right half's values with their reciprocals for the split being built
        long[] rightValues = new long[0];
        double[] rightInv = new double[0];
    }

    // Hold the working memory of one solve with each entry stored as a head word and an operands word
    private static final class State {
        final long target;
        final int n;
        final int full;
        // Keep each subset's sorted values in its own array so workers can build subsets independently
        final long[][] ent;
        final int[] len;
        // Hold the largest value each subset can make which bounds the bitset words it touches
        final long[] max;
        final Scratch[] scratch = new Scratch[2 * THREADS + 2];
        // Hold the bitset words and right-half length the level being built needs
        int words;
        int biggest;

        State(int target, int n) {
            this.target = target;
            this.n = n;
            this.full = (1 << n) - 1;
            this.ent = new long[full + 1][];
            this.len = new int[full + 1];
            this.max = new long[full + 1];
        }

        // Return a worker's buffers sized for the current level
        Scratch scratch(int worker) {
            Scratch w = scratch[worker];
            if (w == null) {
                w = new Scratch();
                scratch[worker] = w;
            }
            // Replace rather than copy since building leaves the bitset clear
            if (words > w.seen.length) {
                w.seen = new long[words];
                w.rank = new int[words];
            }
            if (biggest > w.rightValues.length) {
                w.rightValues = new long[biggest];
                w.rightInv = new double[biggest];
            }
            return w;
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
    private static int emitSplit(State s, Scratch w, int left, int right, int out) {
        final long[] lefts = s.ent[left];
        final long[] rights = s.ent[right];
        final long[] seen = w.seen;
        final long[] tmp = w.tmp;
        final long[] rv = w.rightValues;
        final double[] ri = w.rightInv;
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
            rv[j] = rights[2 * j] & LOW;
            ri[j] = 1.0 / rv[j];
        }
        final int nl = s.len[left];
        for (int i = 0; i < nl; i++) {
            final long a = lefts[2 * i] & LOW;
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

    // Build the sorted reachable values of a subset keeping only the first way found to make each
    private static void build(State s, Scratch w, int mask) {
        final long[] seen = w.seen;
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
            w.tmp = grow(w.tmp, out, out + (int) (2 * bound));
            out = emitSplit(s, w, left, right, out);
        }
        seen[0] &= ~1L;

        final int count = out / 2;
        final long[] sorted = new long[2 * count];
        final long[] tmp = w.tmp;
        if (count < RANK_MIN) {
            // Clear only the words this subset touched and insertion sort the few values
            for (int i = 0; i < count; i++) {
                final long head = tmp[2 * i];
                final long operands = tmp[2 * i + 1];
                final long v = head & LOW;
                seen[(int) (v >>> 6)] = 0;
                int at = 2 * i;
                for (; at > 0 && (sorted[at - 2] & LOW) > v; at -= 2) {
                    sorted[at] = sorted[at - 2];
                    sorted[at + 1] = sorted[at - 1];
                }
                sorted[at] = head;
                sorted[at + 1] = operands;
            }
        } else {
            // Place each value at its rank in the bitset which needs no comparisons
            final int words = (int) (s.max[mask] >>> 6) + 1;
            final int[] rank = w.rank;
            int below = 0;
            for (int k = 0; k < words; k++) {
                rank[k] = below;
                below += Long.bitCount(seen[k]);
            }
            for (int t = 0; t < out; t += 2) {
                final long v = tmp[t] & LOW;
                final int k = (int) (v >>> 6);
                final long lower = seen[k] & ((1L << v) - 1);
                final int at = 2 * (rank[k] + Long.bitCount(lower));
                sorted[at] = tmp[t];
                sorted[at + 1] = tmp[t + 1];
            }
            java.util.Arrays.fill(seen, 0, words, 0);
        }
        s.ent[mask] = sorted;
        s.len[mask] = count;
    }

    // Return the index of value in a subset's entries or -1 when it is absent
    private static int lookup(State s, int mask, long value) {
        final long[] e = s.ent[mask];
        int n = s.len[mask];
        // Skip the search when the value lies outside the subset's range
        if (n == 0 || value < (e[0] & LOW) || value > (e[2 * (n - 1)] & LOW)) {
            return -1;
        }
        int base = 0;
        // Halve the range with a conditional move so unpredictable comparisons cost no mispredicted branch
        while (n > 1) {
            final int half = n >>> 1;
            base += (e[2 * (base + half)] & LOW) <= value ? half : 0;
            n -= half;
        }
        return (e[2 * base] & LOW) == value ? base : -1;
    }

    // Write how one split first makes the target into out at slot and return whether it can
    private static boolean splitExact(State s, int left, int right, long[] out, int slot) {
        final long t = s.target;
        final boolean leftLoop = s.len[left] <= s.len[right];
        final int loopMask = leftLoop ? left : right;
        final int searchMask = leftLoop ? right : left;
        final long[] loop = s.ent[loopMask];
        // Keep the lowest pair as building would since partners are tried in operator order
        long bestA = Long.MAX_VALUE;
        long bestB = Long.MAX_VALUE;
        long bestOp = 0;
        final int end = s.len[loopMask];
        for (int i = 0; i < end; i++) {
            final long n = loop[2 * i] & LOW;
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
        if (bestOp == 0) {
            return false;
        }
        if (bestA >= bestB) {
            out[2 * slot] = template(bestOp, left, right) | t;
            out[2 * slot + 1] = bestA | bestB << 32;
        } else {
            out[2 * slot] = template(bestOp, right, left) | t;
            out[2 * slot + 1] = bestB | bestA << 32;
        }
        return true;
    }

    // Return how the target is first made from any subset of one size by splitting the search across workers
    private static long[] findExact(State s, int[] masks, int[] lefts, int count) {
        final long[] hits = new long[2 * count];
        long scanned = 0;
        for (int k = 0; k < count; k++) {
            scanned += Math.min(s.len[lefts[k]], s.len[masks[k] ^ lefts[k]]);
        }
        // Share only the whole pool's search since smaller sizes usually hit within their first few splits
        if (THREADS == 1 || scanned < FIND_MIN || masks[0] != s.full) {
            // Visit the splits in order since the first one that hits is the answer
            for (int k = 0; k < count; k++) {
                if (splitExact(s, lefts[k], masks[k] ^ lefts[k], hits, k)) {
                    return new long[] {hits[2 * k], hits[2 * k + 1]};
                }
            }
            return null;
        }
        // Keep the earliest split that hits so later splits can stop early
        final AtomicInteger first = new AtomicInteger(Integer.MAX_VALUE);
        RUNNER.run((k, worker) -> {
            if (k < first.get() && splitExact(s, lefts[k], masks[k] ^ lefts[k], hits, k)) {
                first.accumulateAndGet(k, Math::min);
            }
        }, count);
        final int k = first.get();
        return k == Integer.MAX_VALUE ? null : new long[] {hits[2 * k], hits[2 * k + 1]};
    }

    // Build every subset of one size sharing the subsets among the workers when there is enough work
    private static void buildLevel(State s, int[] masks, int count) {
        long pairs = 0;
        final long[] work = new long[count];
        for (int k = 0; k < count; k++) {
            final int mask = masks[k];
            for (int left = (mask - 1) & mask; left != 0; left = (left - 1) & mask) {
                if (left < (mask ^ left)) {
                    work[k] += (long) s.len[left] * s.len[mask ^ left];
                }
            }
            pairs += work[k];
        }
        if (THREADS == 1 || pairs < BUILD_MIN) {
            final Scratch w = s.scratch(0);
            for (int k = 0; k < count; k++) {
                build(s, w, masks[k]);
            }
            return;
        }
        // Hand out the largest subsets first so no worker is left with a big one at the end
        final Integer[] order = new Integer[count];
        for (int k = 0; k < count; k++) {
            order[k] = k;
        }
        java.util.Arrays.sort(order, (x, y) -> Long.compare(work[y], work[x]));
        RUNNER.run((k, worker) -> build(s, s.scratch(worker), masks[order[k]]), count);
    }

    // Write the expression for an entry following its origins back to the pool with brackets when asked
    private static void render(State s, long head, long operands, boolean bracket, StringBuilder out) {
        final long op = head >>> 32 & 255;
        if (op == 0) {
            out.append(head & LOW);
            return;
        }
        final int largerMask = (int) (head >>> 40 & 255);
        final int smallerMask = (int) (head >>> 48 & 255);
        final int larger = lookup(s, largerMask, operands & LOW);
        final int smaller = lookup(s, smallerMask, operands >>> 32);
        if (bracket) {
            out.append('(');
        }
        render(s, s.ent[largerMask][2 * larger], s.ent[largerMask][2 * larger + 1], true, out);
        out.append(' ').append((char) op).append(' ');
        render(s, s.ent[smallerMask][2 * smaller], s.ent[smallerMask][2 * smaller + 1], true, out);
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

        // List each size's subsets in mask order and their splits in building order for the searches
        final int[][] sizeMasks = new int[n + 1][];
        final int[][] splitMasks = new int[n + 1][];
        final int[][] splitLefts = new int[n + 1][];
        for (int size = 1; size <= n; size++) {
            int subsets = 0;
            int splits = 0;
            for (int mask = 1; mask <= s.full; mask++) {
                if (Integer.bitCount(mask) == size) {
                    subsets++;
                    splits += (1 << (size - 1)) - 1;
                }
            }
            sizeMasks[size] = new int[subsets];
            splitMasks[size] = new int[splits];
            splitLefts[size] = new int[splits];
            int m = 0;
            int k = 0;
            for (int mask = 1; mask <= s.full; mask++) {
                if (Integer.bitCount(mask) != size) {
                    continue;
                }
                sizeMasks[size][m++] = mask;
                for (int left = (mask - 1) & mask; left != 0; left = (left - 1) & mask) {
                    if (left < (mask ^ left)) {
                        splitMasks[size][k] = mask;
                        splitLefts[size][k++] = left;
                    }
                }
            }
        }

        // Store each pool number as a one-number subset
        long[] best = null;
        for (int i = 0; i < n; i++) {
            s.ent[1 << i] = new long[] {pool[i], 0};
            s.len[1 << i] = 1;
            if (best == null && pool[i] == target) {
                best = new long[] {pool[i], 0};
            }
        }

        // Work through subsets smallest first stopping at the first size that hits the target
        for (int size = 2; size <= n && best == null; size++) {
            best = findExact(s, splitMasks[size], splitLefts[size], splitMasks[size].length);
            // Skip building the whole pool's values since no larger subset is made from them
            if (best != null || size == n) {
                break;
            }
            int biggest = 0;
            for (int mask = 1; mask <= s.full; mask++) {
                biggest = Math.max(biggest, s.len[mask]);
            }
            s.biggest = biggest;
            s.words = (int) (largest[size] >>> 6) + 1;
            buildLevel(s, sizeMasks[size], sizeMasks[size].length);
        }

        if (best == null) {
            best = n == 1 ? new long[] {pool[0], 0} : closest(s, splitMasks[n], splitLefts[n]);
        }

        // Render without outer brackets which matches stripping them from the bracketed form
        final StringBuilder expr = new StringBuilder();
        render(s, best[0], best[1], false, expr);
        return new Result((int) (best[0] & LOW), expr.toString());
    }

    // Write the closest whole-pool value one split makes with its first way into the slot's arrays
    private static void splitClosest(State s, int left, int right, long[] dist, long[] found, int slot) {
        final long t = s.target;
        final long[] lefts = s.ent[left];
        final long[] rights = s.ent[right];
        long bestD = NONE;
        long bestV = NONE;
        long head = 0;
        long operands = 0;
        for (int i = 0; i < s.len[left]; i++) {
            final long a = lefts[2 * i] & LOW;
            for (int j = 0; j < s.len[right]; j++) {
                final long b = rights[2 * j] & LOW;
                final long x = Math.max(a, b);
                final long y = Math.min(a, b);
                final int lm = b <= a ? left : right;
                final int sm = b <= a ? right : left;
                // Try the operators in order so the first way of making the closest value wins
                for (int k = 0; k < 4; k++) {
                    final long v = switch (k) {
                        case 0 -> x + y;
                        case 1 -> x != y ? x - y : 0;
                        case 2 -> y != 1 ? x * y : 0;
                        default -> y != 1 && x % y == 0 ? x / y : 0;
                    };
                    final long d = Math.abs(v - t);
                    // Prefer the lower value on equal distance to break ties the same way every run
                    if (v != 0 && (d < bestD || (d == bestD && v < bestV))) {
                        bestD = d;
                        bestV = v;
                        final long op = k == 0 ? OP_ADD : k == 1 ? OP_SUB : k == 2 ? OP_MUL : OP_DIV;
                        head = template(op, lm, sm) | v;
                        operands = x | y << 32;
                    }
                }
            }
        }
        dist[slot] = bestD;
        found[2 * slot] = head;
        found[2 * slot + 1] = operands;
    }

    // Return the closest value as a head and operands pair when no subset can make the target
    private static long[] closest(State s, int[] masks, int[] lefts) {
        final long t = s.target;
        long[] best = null;
        // Rank by distance from the target then by how many numbers are used so the simplest answer wins
        long bestDistance = Long.MAX_VALUE;
        int bestUsed = 99;
        for (int mask = 1; mask < s.full; mask++) {
            final int used = Integer.bitCount(mask);
            final long[] e = s.ent[mask];
            for (int i = 0; i < s.len[mask]; i++) {
                final long d = Math.abs((e[2 * i] & LOW) - t);
                if (d < bestDistance || (d == bestDistance && used < bestUsed)) {
                    best = new long[] {e[2 * i], e[2 * i + 1]};
                    bestDistance = d;
                    bestUsed = used;
                }
            }
        }
        // Check the whole pool's values split by split since no larger subset is built from them
        final int count = masks.length;
        final long[] dist = new long[count];
        final long[] found = new long[2 * count];
        long pairs = 0;
        for (int k = 0; k < count; k++) {
            pairs += (long) s.len[lefts[k]] * s.len[masks[k] ^ lefts[k]];
        }
        if (THREADS == 1 || pairs < WHOLE_MIN) {
            for (int k = 0; k < count; k++) {
                splitClosest(s, lefts[k], masks[k] ^ lefts[k], dist, found, k);
            }
        } else {
            RUNNER.run((k, worker) -> splitClosest(s, lefts[k], masks[k] ^ lefts[k], dist, found, k), count);
        }
        // Combine the splits in order keeping the earliest on a tie as the sequential pass would
        int pick = -1;
        for (int k = 0; k < count; k++) {
            if (dist[k] == NONE) {
                continue;
            }
            if (pick < 0 || dist[k] < dist[pick]
                    || (dist[k] == dist[pick] && (found[2 * k] & LOW) < (found[2 * pick] & LOW))) {
                pick = k;
            }
        }
        // Fall back to the whole pool only when it gets strictly closer as it uses the most numbers
        return pick >= 0 && dist[pick] < bestDistance ? new long[] {found[2 * pick], found[2 * pick + 1]} : best;
    }
}
