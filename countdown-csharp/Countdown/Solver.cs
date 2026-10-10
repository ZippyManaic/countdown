// Work out the simplest Countdown expression that hits a target or gets closest to it
using System.Numerics;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using System.Text;

namespace Countdown;

[SkipLocalsInit]
public static unsafe class Solver
{
    // Sort subsets with fewer values than this by insertion rather than by rank in the bitset
    private const int RankMin = 16;
    // Radix sort a subset when its bitset has more than this many words per value
    private const int Sparse = 64;
    private const ulong OpAdd = '+';
    private const ulong OpSub = '-';
    private const ulong OpMul = '*';
    private const ulong OpDiv = '/';
    private const ulong Low = 0xFFFF_FFFF;

    // Record a reachable value with how it was made from the larger and smaller of two values in disjoint subsets
    private struct Entry
    {
        // Pack value, operator (zero for a pool number), larger mask and smaller mask from the low bits up
        public ulong Head;
        // Pack the larger operand in the low half and the smaller in the high half
        public ulong Operands;

        public readonly ulong Value => Head & Low;
    }

    // Hold the working memory of one solve in unmanaged buffers freed when the solve ends
    private struct State
    {
        public ulong Target;
        public int Full;
        // Keep every subset's sorted values back to back in one arena
        public Entry* Arena;
        public nint Top, Cap;
        public fixed int Off[256];
        public fixed int Len[256];
        // Hold the largest value each subset can make which bounds the bitset words it touches
        public fixed ulong Max[256];
        // Hold one bit per value seen in the subset being built
        public ulong* Seen;
        public nint SeenWords;
        // Collect a subset's new values here before they are sorted into the arena
        public Entry* Tmp;
        public nint TmpCap;
        // Hold the count of values below each bitset word for ranking
        public uint* Rank;
        // Hold the right half's values with their reciprocals for the split being built
        public ulong* RightValues;
        public double* RightInv;
        public nint RightCap;
    }

    // Grow an entry buffer to at least need entries by doubling keeping its first keep entries
    private static Entry* Reserve(Entry* items, ref nint cap, nint keep, nint need)
    {
        if (need <= cap) return items;
        var size = Math.Max(cap, 1024);
        while (size < need) size *= 2;
        var grown = (Entry*)NativeMemory.Realloc(items, (nuint)(size * sizeof(Entry)));
        cap = size;
        return grown;
    }

    // Return the operator and masks of an entry shifted above its value
    [MethodImpl(MethodImplOptions.AggressiveInlining)]
    private static ulong Template(ulong op, int largerMask, int smallerMask) =>
        (op | (ulong)largerMask << 8 | (ulong)smallerMask << 16) << 32;

    // Store a value and return the next slot which moves on only if the bitset shows the value is new
    [MethodImpl(MethodImplOptions.AggressiveInlining)]
    private static Entry* Emit(ulong* seen, Entry* output, ulong v, ulong tmpl, ulong operands)
    {
        var w = seen[v >> 6];
        seen[v >> 6] = w | 1UL << (int)v;
        output->Head = tmpl | v;
        output->Operands = operands;
        return output + (int)(~w >> (int)v & 1);
    }

    // Return x divided by y when the division is exact and zero otherwise using the reciprocal of y
    [MethodImpl(MethodImplOptions.AggressiveInlining)]
    private static ulong Exact(ulong x, ulong y, double inv)
    {
        var q = (ulong)(x * inv + 0.5);
        // Mask with arithmetic so the comparison costs no mispredicted branch
        return q & (0UL - (q * y == x ? 1UL : 0UL));
    }

    // Append every new value from pairing each left value with each right value of one split and return the new end
    private static Entry* EmitSplit(State* s, int left, int right, Entry* output)
    {
        var seen = s->Seen;
        var rv = s->RightValues;
        var ri = s->RightInv;
        var lefts = s->Arena + s->Off[left];
        var rights = s->Arena + s->Off[right];
        int nl = s->Len[left], nr = s->Len[right];
        ulong tlAdd = Template(OpAdd, left, right), tlSub = Template(OpSub, left, right);
        ulong tlMul = Template(OpMul, left, right), tlDiv = Template(OpDiv, left, right);
        ulong trAdd = Template(OpAdd, right, left), trSub = Template(OpSub, right, left);
        ulong trMul = Template(OpMul, right, left), trDiv = Template(OpDiv, right, left);
        // Invert each right value once per split rather than once per pair
        for (var j = 0; j < nr; j++)
        {
            rv[j] = rights[j].Value;
            ri[j] = 1.0 / rv[j];
        }
        for (var i = 0; i < nl; i++)
        {
            var a = lefts[i].Value;
            var j = 0;
            // Pair with right values up to a first where a is the larger and ties go left
            for (; j < nr && rv[j] <= a; j++)
            {
                var b = rv[j];
                var operands = a | b << 32;
                output = Emit(seen, output, a + b, tlAdd, operands);
                // Skip a zero result since every intermediate value must be a positive integer
                if (a != b) output = Emit(seen, output, a - b, tlSub, operands);
                // Skip multiplying and dividing by one as they never produce a new value
                if (b != 1)
                {
                    output = Emit(seen, output, a * b, tlMul, operands);
                    output = Emit(seen, output, Exact(a, b, ri[j]), tlDiv, operands);
                }
            }
            // Pair with the remaining larger right values where a is the smaller
            var ia = 1.0 / a;
            for (; j < nr; j++)
            {
                var b = rv[j];
                var operands = b | a << 32;
                output = Emit(seen, output, b + a, trAdd, operands);
                output = Emit(seen, output, b - a, trSub, operands);
                if (a != 1)
                {
                    output = Emit(seen, output, b * a, trMul, operands);
                    output = Emit(seen, output, Exact(b, a, ia), trDiv, operands);
                }
            }
        }
        return output;
    }

    // Build the sorted reachable values of a subset into the arena keeping only the first way found to make each
    private static void Build(State* s, int mask)
    {
        var seen = s->Seen;
        nint count = 0;
        // Mark zero as seen so inexact divisions never become entries
        seen[0] |= 1;
        for (var left = (mask - 1) & mask; left != 0; left = (left - 1) & mask)
        {
            var right = mask ^ left;
            // Visit each split once rather than once per ordering
            if (left >= right) continue;
            // Reserve room for every pair's results plus the one slot each store may write past the end
            var bound = (nint)Math.Min(4UL * (ulong)s->Len[left] * (ulong)s->Len[right], s->Max[mask]) + 1;
            s->Tmp = Reserve(s->Tmp, ref s->TmpCap, count, count + bound);
            count = (nint)(EmitSplit(s, left, right, s->Tmp + count) - s->Tmp);
        }
        seen[0] &= ~1UL;

        s->Arena = Reserve(s->Arena, ref s->Cap, s->Top, s->Top + count);
        var sorted = s->Arena + s->Top;
        var tmp = s->Tmp;
        if (count < RankMin)
        {
            // Clear only the words this subset touched and insertion sort the few values
            for (nint i = 0; i < count; i++)
            {
                var e = tmp[i];
                seen[e.Value >> 6] = 0;
                var k = i;
                for (; k > 0 && sorted[k - 1].Value > e.Value; k--) sorted[k] = sorted[k - 1];
                sorted[k] = e;
            }
        }
        else if ((nint)(s->Max[mask] >> 6) + 1 > Sparse * count)
        {
            // Radix sort sparse subsets so the cost follows the values found rather than the range they could span
            var counts = stackalloc uint[3 * 2048];
            new Span<uint>(counts, 3 * 2048).Clear();
            for (nint i = 0; i < count; i++)
            {
                var v = (uint)tmp[i].Head;
                seen[v >> 6] = 0;
                counts[v & 2047]++;
                counts[2048 + (v >> 11 & 2047)]++;
                counts[4096 + (v >> 22)]++;
            }
            Entry* from = tmp, to = sorted;
            for (var pass = 0; pass < 3; pass++)
            {
                var c = counts + 2048 * pass;
                var shift = 11 * pass;
                uint sum = 0;
                for (var d = 0; d < 2048; d++)
                {
                    var k = c[d];
                    c[d] = sum;
                    sum += k;
                }
                for (nint i = 0; i < count; i++) to[c[(uint)from[i].Head >> shift & 2047]++] = from[i];
                var t = from;
                from = to;
                to = t;
            }
        }
        else
        {
            // Place each value at its rank in the bitset which needs no comparisons
            var words = (nint)(s->Max[mask] >> 6) + 1;
            var rank = s->Rank;
            uint below = 0;
            for (nint w = 0; w < words; w++)
            {
                rank[w] = below;
                below += (uint)BitOperations.PopCount(seen[w]);
            }
            for (nint i = 0; i < count; i++)
            {
                var v = tmp[i].Value;
                var lower = seen[v >> 6] & ((1UL << (int)v) - 1);
                sorted[rank[v >> 6] + (uint)BitOperations.PopCount(lower)] = tmp[i];
            }
            new Span<ulong>(seen, (int)words).Clear();
        }
        s->Off[mask] = (int)s->Top;
        s->Len[mask] = (int)count;
        s->Top += count;
    }

    // Return the entry holding value in a subset or null when it is absent
    [MethodImpl(MethodImplOptions.AggressiveInlining)]
    private static Entry* Lookup(State* s, int mask, ulong value)
    {
        var bas = s->Arena + s->Off[mask];
        var n = s->Len[mask];
        // Skip the search when the value lies outside the subset's range
        if (n == 0 || value < bas[0].Value || value > bas[n - 1].Value) return null;
        // Halve the range with a conditional move so unpredictable comparisons cost no mispredicted branch
        while (n > 1)
        {
            var half = n >> 1;
            bas += bas[half].Value <= value ? half : 0;
            n -= half;
        }
        return bas->Value == value ? bas : null;
    }

    // Find how the target is first made from a subset without building all of its values
    private static bool FindExact(State* s, int mask, out Entry hit)
    {
        var t = s->Target;
        for (var left = (mask - 1) & mask; left != 0; left = (left - 1) & mask)
        {
            var right = mask ^ left;
            // Visit splits in the same order as building so the same origin wins
            if (left >= right) continue;
            var leftLoop = s->Len[left] <= s->Len[right];
            var loopMask = leftLoop ? left : right;
            var searchMask = leftLoop ? right : left;
            // Keep the lowest pair as building would since partners are tried in operator order
            ulong bestA = ulong.MaxValue, bestB = ulong.MaxValue, bestOp = 0;
            var values = s->Arena + s->Off[loopMask];
            var count = s->Len[loopMask];
            for (var i = 0; i < count; i++)
            {
                var n = values[i].Value;
                // Try each number that combines with n to make the target in operator order
                if (leftLoop)
                {
                    if (t > n && t - n < bestB && Lookup(s, searchMask, t - n) != null) { bestA = n; bestB = t - n; bestOp = OpAdd; }
                    if (n > t && n - t < bestB && Lookup(s, searchMask, n - t) != null) { bestA = n; bestB = n - t; bestOp = OpSub; }
                    if (n + t < bestB && Lookup(s, searchMask, n + t) != null) { bestA = n; bestB = n + t; bestOp = OpSub; }
                    // Divide only when the quotient could be at least two since neither operand may be one
                    if (n != 1 && 2 * n <= t && t % n == 0 && t / n < bestB && Lookup(s, searchMask, t / n) != null) { bestA = n; bestB = t / n; bestOp = OpMul; }
                    if (n >= 2 * t && n % t == 0 && n / t < bestB && Lookup(s, searchMask, n / t) != null) { bestA = n; bestB = n / t; bestOp = OpDiv; }
                    if (n != 1 && n * t < bestB && Lookup(s, searchMask, n * t) != null) { bestA = n; bestB = n * t; bestOp = OpDiv; }
                    // Take the first left value with any partner since left values ascend
                    if (bestOp != 0) break;
                }
                else
                {
                    if (t > n && t - n < bestA && Lookup(s, searchMask, t - n) != null) { bestA = t - n; bestB = n; bestOp = OpAdd; }
                    if (n > t && n - t < bestA && Lookup(s, searchMask, n - t) != null) { bestA = n - t; bestB = n; bestOp = OpSub; }
                    if (n + t < bestA && Lookup(s, searchMask, n + t) != null) { bestA = n + t; bestB = n; bestOp = OpSub; }
                    if (n != 1 && 2 * n <= t && t % n == 0 && t / n < bestA && Lookup(s, searchMask, t / n) != null) { bestA = t / n; bestB = n; bestOp = OpMul; }
                    if (n >= 2 * t && n % t == 0 && n / t < bestA && Lookup(s, searchMask, n / t) != null) { bestA = n / t; bestB = n; bestOp = OpDiv; }
                    if (n != 1 && n * t < bestA && Lookup(s, searchMask, n * t) != null) { bestA = n * t; bestB = n; bestOp = OpDiv; }
                }
            }
            if (bestOp != 0)
            {
                hit = bestA >= bestB
                    ? new Entry { Head = Template(bestOp, left, right) | t, Operands = bestA | bestB << 32 }
                    : new Entry { Head = Template(bestOp, right, left) | t, Operands = bestB | bestA << 32 };
                return true;
            }
        }
        hit = default;
        return false;
    }

    // Write the expression for an entry following its origins back to the pool with brackets when asked
    private static void Render(State* s, Entry e, bool bracket, StringBuilder output)
    {
        var op = (char)(e.Head >> 32 & 255);
        if (op == 0)
        {
            output.Append(e.Value);
            return;
        }
        if (bracket) output.Append('(');
        Render(s, *Lookup(s, (int)(e.Head >> 40 & 255), e.Operands & Low), true, output);
        output.Append(' ').Append(op).Append(' ');
        Render(s, *Lookup(s, (int)(e.Head >> 48 & 255), e.Operands >> 32), true, output);
        if (bracket) output.Append(')');
    }

    // Return the simplest expression that hits the target or gets closest to it with its value
    public static (int Value, string Expr) Solve(int target, int[] pool)
    {
        State state = default;
        var s = &state;
        try
        {
            return SolveInto(s, target, pool);
        }
        finally
        {
            NativeMemory.Free(s->Arena);
            NativeMemory.Free(s->Tmp);
            NativeMemory.Free(s->Seen);
            NativeMemory.Free(s->Rank);
            NativeMemory.Free(s->RightValues);
            NativeMemory.Free(s->RightInv);
        }
    }

    private static (int Value, string Expr) SolveInto(State* s, int target, int[] pool)
    {
        var n = pool.Length;
        s->Target = (ulong)target;
        s->Full = (1 << n) - 1;

        // Work out each subset's largest value since subtracting and dividing never exceed the larger operand
        var largest = stackalloc ulong[n + 2];
        new Span<ulong>(largest, n + 2).Clear();
        for (var mask = 1; mask <= s->Full; mask++)
        {
            if ((mask & (mask - 1)) == 0)
            {
                s->Max[mask] = (ulong)pool[BitOperations.TrailingZeroCount(mask)];
            }
            else
            {
                for (var left = (mask - 1) & mask; left != 0; left = (left - 1) & mask)
                {
                    ulong a = s->Max[left], b = s->Max[mask ^ left];
                    s->Max[mask] = Math.Max(s->Max[mask], Math.Max(a * b, a + b));
                }
            }
            // Track the largest value of each size so the bitset only grows when bigger subsets are built
            var size = BitOperations.PopCount((uint)mask);
            largest[size] = Math.Max(largest[size], s->Max[mask]);
        }

        // Store each pool number as a one-number subset
        s->Arena = Reserve(s->Arena, ref s->Cap, 0, 4096);
        Entry best = default;
        var solved = false;
        for (var i = 0; i < n; i++)
        {
            s->Arena[i] = new Entry { Head = (ulong)pool[i], Operands = 0 };
            s->Off[1 << i] = i;
            s->Len[1 << i] = 1;
            if (!solved && pool[i] == target)
            {
                best = s->Arena[i];
                solved = true;
            }
        }
        s->Top = n;

        // Work through subsets smallest first stopping at the first size that hits the target
        for (var size = 2; size <= n && !solved; size++)
        {
            // Keep the lowest matching subset of this size to break ties the same way every run
            for (var mask = 1; mask <= s->Full && !solved; mask++)
            {
                if (BitOperations.PopCount((uint)mask) == size) solved = FindExact(s, mask, out best);
            }
            // Skip building the whole pool's values since no larger subset is made from them
            if (solved || size == n) break;
            ReserveRights(s);
            // Replace rather than copy since building leaves the bitset clear
            var words = (nint)(largest[size] >> 6) + 1;
            if (words > s->SeenWords)
            {
                NativeMemory.Free(s->Seen);
                NativeMemory.Free(s->Rank);
                s->Seen = (ulong*)NativeMemory.AllocZeroed((nuint)words, sizeof(ulong));
                s->Rank = (uint*)NativeMemory.Alloc((nuint)words, sizeof(uint));
                s->SeenWords = words;
            }
            for (var mask = 1; mask <= s->Full; mask++)
            {
                if (BitOperations.PopCount((uint)mask) == size) Build(s, mask);
            }
        }

        if (!solved) best = Closest(s, n);

        // Render without outer brackets which matches stripping them from the bracketed form
        var expr = new StringBuilder();
        Render(s, best, false, expr);
        return ((int)best.Value, expr.ToString());
    }

    // Make room for the values and reciprocals of the largest subset built so far
    private static void ReserveRights(State* s)
    {
        nint biggest = 0;
        for (var mask = 1; mask <= s->Full; mask++) biggest = Math.Max(biggest, s->Len[mask]);
        if (biggest <= s->RightCap) return;
        s->RightValues = (ulong*)NativeMemory.Realloc(s->RightValues, (nuint)(biggest * sizeof(ulong)));
        s->RightInv = (double*)NativeMemory.Realloc(s->RightInv, (nuint)(biggest * sizeof(double)));
        s->RightCap = biggest;
    }

    // Return the closest value when no subset can make the target
    private static Entry Closest(State* s, int n)
    {
        var t = s->Target;
        // Rank by distance from the target then by how many numbers are used so the simplest answer wins
        Entry best = default;
        ulong bestDistance = ulong.MaxValue;
        var bestUsed = 99;
        // Include a one-number pool here since the whole-pool pass below needs at least two numbers
        var last = n > 1 ? s->Full - 1 : s->Full;
        for (var mask = 1; mask <= last; mask++)
        {
            var used = BitOperations.PopCount((uint)mask);
            var values = s->Arena + s->Off[mask];
            for (var i = 0; i < s->Len[mask]; i++)
            {
                var v = values[i].Value;
                var d = v > t ? v - t : t - v;
                if (d < bestDistance || (d == bestDistance && used < bestUsed))
                {
                    best = values[i];
                    bestDistance = d;
                    bestUsed = used;
                }
            }
        }
        if (n == 1) return best;
        ReserveRights(s);
        // Check the whole pool's values as they are made since no larger subset is built from them
        var whole = new Entry { Head = Low };
        var wholeDistance = ulong.MaxValue;
        var full = s->Full;
        for (var left = (full - 1) & full; left != 0; left = (left - 1) & full)
        {
            var right = full ^ left;
            if (left >= right) continue;
            var lefts = s->Arena + s->Off[left];
            var rights = s->Arena + s->Off[right];
            for (var i = 0; i < s->Len[left]; i++)
            {
                for (var j = 0; j < s->Len[right]; j++)
                {
                    ulong a = lefts[i].Value, b = rights[j].Value;
                    ulong x = Math.Max(a, b), y = Math.Min(a, b);
                    int lm = b <= a ? left : right, sm = b <= a ? right : left;
                    var operands = x | y << 32;
                    Check(x + y, OpAdd);
                    if (x != y) Check(x - y, OpSub);
                    if (y != 1)
                    {
                        Check(x * y, OpMul);
                        if (x % y == 0) Check(x / y, OpDiv);
                    }

                    // Keep a value if it is closer to the target or equally close and lower
                    void Check(ulong v, ulong op)
                    {
                        var d = v > t ? v - t : t - v;
                        if (d < wholeDistance || (d == wholeDistance && v < whole.Value))
                        {
                            wholeDistance = d;
                            whole = new Entry { Head = Template(op, lm, sm) | v, Operands = operands };
                        }
                    }
                }
            }
        }
        // Fall back to the whole pool only when it gets strictly closer as it uses the most numbers
        return wholeDistance < bestDistance ? whole : best;
    }
}
