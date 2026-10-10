// Work out the simplest Countdown expression that hits a target or gets closest to it
package countdown

// Hold an answer with its value and expression
data class Result(val value: Int, val expr: String)

// Sort subsets with fewer values than this by insertion rather than by rank in the bitset
private const val RANK_MIN = 16
private const val OP_ADD = '+'.code.toLong()
private const val OP_SUB = '-'.code.toLong()
private const val OP_MUL = '*'.code.toLong()
private const val OP_DIV = '/'.code.toLong()
private const val LOW = 0xFFFF_FFFFL

// Hold the working memory of one solve with each entry stored as a head word and an operands word
private class State(val target: Long, val n: Int) {
    val full = (1 shl n) - 1
    // Keep every subset's sorted values back to back in one arena
    var arena = LongArray(2 * 1024)
    var top = 0
    val off = IntArray(full + 1)
    val len = IntArray(full + 1)
    // Hold the largest value each subset can make which bounds the bitset words it touches
    val max = LongArray(full + 1)
    // Hold one bit per value seen in the subset being built
    var seen = LongArray(0)
    // Collect a subset's new values here before they are sorted into the arena
    var tmp = LongArray(2 * 1024)
    // Hold the count of values below each bitset word for ranking
    var rank = IntArray(0)
    // Hold the right half's values with their reciprocals for the split being built
    var rightValues = LongArray(0)
    var rightInv = DoubleArray(0)
}

// Return the operator and masks of an entry shifted above its value
private fun template(op: Long, largerMask: Int, smallerMask: Int): Long =
    (op or (largerMask.toLong() shl 8) or (smallerMask.toLong() shl 16)) shl 32

// Return a copy of words with room for at least need words keeping its first keep words
private fun grow(words: LongArray, keep: Int, need: Int): LongArray {
    if (need <= words.size) return words
    var size = maxOf(words.size, 2048)
    while (size < need) size *= 2
    val grown = LongArray(size)
    System.arraycopy(words, 0, grown, 0, keep)
    return grown
}

// Store a value and return the next slot which moves on only if the bitset shows the value is new
@Suppress("NOTHING_TO_INLINE")
private inline fun emit(seen: LongArray, tmp: LongArray, out: Int, v: Long, tmpl: Long, operands: Long): Int {
    val word = (v ushr 6).toInt()
    val w = seen[word]
    seen[word] = w or (1L shl v.toInt())
    tmp[out] = tmpl or v
    tmp[out + 1] = operands
    return out + (((w.inv() ushr v.toInt()) and 1L).toInt() shl 1)
}

// Return x divided by y when the division is exact and zero otherwise using the reciprocal of y
@Suppress("NOTHING_TO_INLINE")
private inline fun exact(x: Long, y: Long, inv: Double): Long {
    val q = (x * inv + 0.5).toLong()
    val miss = q * y xor x
    // Turn a zero difference into an all-ones mask with arithmetic so it costs no mispredicted branch
    return q and (((miss or -miss) ushr 63) - 1)
}

// Append every new value from pairing each left value with each right value of one split and return the new end
private fun emitSplit(s: State, left: Int, right: Int, start: Int): Int {
    var out = start
    val arena = s.arena
    val seen = s.seen
    val tmp = s.tmp
    val rv = s.rightValues
    val ri = s.rightInv
    val nr = s.len[right]
    val tlAdd = template(OP_ADD, left, right)
    val tlSub = template(OP_SUB, left, right)
    val tlMul = template(OP_MUL, left, right)
    val tlDiv = template(OP_DIV, left, right)
    val trAdd = template(OP_ADD, right, left)
    val trSub = template(OP_SUB, right, left)
    val trMul = template(OP_MUL, right, left)
    val trDiv = template(OP_DIV, right, left)
    // Invert each right value once per split rather than once per pair
    val roff = s.off[right]
    for (j in 0 until nr) {
        rv[j] = arena[2 * (roff + j)] and LOW
        ri[j] = 1.0 / rv[j]
    }
    val end = s.off[left] + s.len[left]
    for (i in s.off[left] until end) {
        val a = arena[2 * i] and LOW
        var j = 0
        // Pair with right values up to a first where a is the larger and ties go left
        while (j < nr && rv[j] <= a) {
            val b = rv[j]
            val operands = a or (b shl 32)
            out = emit(seen, tmp, out, a + b, tlAdd, operands)
            // Skip a zero result since every intermediate value must be a positive integer
            if (a != b) out = emit(seen, tmp, out, a - b, tlSub, operands)
            // Skip multiplying and dividing by one as they never produce a new value
            if (b != 1L) {
                out = emit(seen, tmp, out, a * b, tlMul, operands)
                out = emit(seen, tmp, out, exact(a, b, ri[j]), tlDiv, operands)
            }
            j++
        }
        // Pair with the remaining larger right values where a is the smaller
        val ia = 1.0 / a
        while (j < nr) {
            val b = rv[j]
            val operands = b or (a shl 32)
            out = emit(seen, tmp, out, b + a, trAdd, operands)
            out = emit(seen, tmp, out, b - a, trSub, operands)
            if (a != 1L) {
                out = emit(seen, tmp, out, b * a, trMul, operands)
                out = emit(seen, tmp, out, exact(b, a, ia), trDiv, operands)
            }
            j++
        }
    }
    return out
}

// Build the sorted reachable values of a subset into the arena keeping only the first way found to make each
private fun build(s: State, mask: Int) {
    val seen = s.seen
    var out = 0
    // Mark zero as seen so inexact divisions never become entries
    seen[0] = seen[0] or 1L
    var left = (mask - 1) and mask
    while (left != 0) {
        val right = mask xor left
        // Visit each split once rather than once per ordering
        if (left < right) {
            // Reserve room for every pair's results plus the one slot each store may write past the end
            val bound = minOf(4L * s.len[left] * s.len[right], s.max[mask]) + 1
            s.tmp = grow(s.tmp, out, out + (2 * bound).toInt())
            out = emitSplit(s, left, right, out)
        }
        left = (left - 1) and mask
    }
    seen[0] = seen[0] and 1L.inv()

    val count = out / 2
    s.arena = grow(s.arena, 2 * s.top, 2 * (s.top + count))
    val arena = s.arena
    val tmp = s.tmp
    val base = 2 * s.top
    if (count < RANK_MIN) {
        // Clear only the words this subset touched and insertion sort the few values
        for (i in 0 until count) {
            val head = tmp[2 * i]
            val operands = tmp[2 * i + 1]
            val v = head and LOW
            seen[(v ushr 6).toInt()] = 0
            var at = base + 2 * i
            while (at > base && (arena[at - 2] and LOW) > v) {
                arena[at] = arena[at - 2]
                arena[at + 1] = arena[at - 1]
                at -= 2
            }
            arena[at] = head
            arena[at + 1] = operands
        }
    } else {
        // Place each value at its rank in the bitset which needs no comparisons
        val words = (s.max[mask] ushr 6).toInt() + 1
        val rank = s.rank
        var below = 0
        for (w in 0 until words) {
            rank[w] = below
            below += java.lang.Long.bitCount(seen[w])
        }
        var t = 0
        while (t < out) {
            val v = tmp[t] and LOW
            val w = (v ushr 6).toInt()
            val lower = seen[w] and ((1L shl v.toInt()) - 1)
            val at = base + 2 * (rank[w] + java.lang.Long.bitCount(lower))
            arena[at] = tmp[t]
            arena[at + 1] = tmp[t + 1]
            t += 2
        }
        java.util.Arrays.fill(seen, 0, words, 0L)
    }
    s.off[mask] = s.top
    s.len[mask] = count
    s.top += count
}

// Return the arena index of value in a subset or -1 when it is absent
private fun lookup(s: State, mask: Int, value: Long): Int {
    val arena = s.arena
    var base = s.off[mask]
    var n = s.len[mask]
    // Skip the search when the value lies outside the subset's range
    if (n == 0 || value < (arena[2 * base] and LOW) || value > (arena[2 * (base + n - 1)] and LOW)) return -1
    // Halve the range with a conditional move so unpredictable comparisons cost no mispredicted branch
    while (n > 1) {
        val half = n ushr 1
        base += if ((arena[2 * (base + half)] and LOW) <= value) half else 0
        n -= half
    }
    return if ((arena[2 * base] and LOW) == value) base else -1
}

// Return how the target is first made from a subset as a head and operands pair without building all of its values
private fun findExact(s: State, mask: Int): LongArray? {
    val t = s.target
    val arena = s.arena
    var left = (mask - 1) and mask
    while (left != 0) {
        val right = mask xor left
        // Visit splits in the same order as building so the same origin wins
        if (left < right) {
            val leftLoop = s.len[left] <= s.len[right]
            val loopMask = if (leftLoop) left else right
            val searchMask = if (leftLoop) right else left
            // Keep the lowest pair as building would since partners are tried in operator order
            var bestA = Long.MAX_VALUE
            var bestB = Long.MAX_VALUE
            var bestOp = 0L
            val end = s.off[loopMask] + s.len[loopMask]
            for (i in s.off[loopMask] until end) {
                val n = arena[2 * i] and LOW
                // Bound each partner by the best so far on the searched side
                val bound = if (leftLoop) bestB else bestA
                var p = 0L
                var op = 0L
                // Try each number that combines with n to make the target in operator order keeping the lowest
                if (t > n && t - n < bound && lookup(s, searchMask, t - n) >= 0) { p = t - n; op = OP_ADD }
                if (op == 0L && n > t && n - t < bound && lookup(s, searchMask, n - t) >= 0) { p = n - t; op = OP_SUB }
                if (op == 0L && n + t < bound && lookup(s, searchMask, n + t) >= 0) { p = n + t; op = OP_SUB }
                // Divide only when the quotient could be at least two since neither operand may be one
                if (n != 1L && 2 * n <= t && t % n == 0L && t / n < (if (op != 0L) p else bound) &&
                    lookup(s, searchMask, t / n) >= 0) { p = t / n; op = OP_MUL }
                if (n >= 2 * t && n % t == 0L && n / t < (if (op != 0L) p else bound) &&
                    lookup(s, searchMask, n / t) >= 0) { p = n / t; op = OP_DIV }
                if (n != 1L && n * t < (if (op != 0L) p else bound) &&
                    lookup(s, searchMask, n * t) >= 0) { p = n * t; op = OP_DIV }
                if (op != 0L) {
                    if (leftLoop) {
                        bestA = n; bestB = p; bestOp = op
                        // Take the first left value with any partner since left values ascend
                        break
                    }
                    bestA = p; bestB = n; bestOp = op
                }
            }
            if (bestOp != 0L) {
                return if (bestA >= bestB) longArrayOf(template(bestOp, left, right) or t, bestA or (bestB shl 32))
                else longArrayOf(template(bestOp, right, left) or t, bestB or (bestA shl 32))
            }
        }
        left = (left - 1) and mask
    }
    return null
}

// Write the expression for an entry following its origins back to the pool with brackets when asked
private fun render(s: State, head: Long, operands: Long, bracket: Boolean, out: StringBuilder) {
    val op = (head ushr 32) and 255
    if (op == 0L) {
        out.append(head and LOW)
        return
    }
    val larger = lookup(s, ((head ushr 40) and 255).toInt(), operands and LOW)
    val smaller = lookup(s, ((head ushr 48) and 255).toInt(), operands ushr 32)
    if (bracket) out.append('(')
    render(s, s.arena[2 * larger], s.arena[2 * larger + 1], true, out)
    out.append(' ').append(op.toInt().toChar()).append(' ')
    render(s, s.arena[2 * smaller], s.arena[2 * smaller + 1], true, out)
    if (bracket) out.append(')')
}

// Return the closest value as a head and operands pair when no subset can make the target
private fun closest(s: State): LongArray? {
    val arena = s.arena
    val t = s.target
    var best: LongArray? = null
    // Rank by distance from the target then by how many numbers are used so the simplest answer wins
    var bestDistance = Long.MAX_VALUE
    var bestUsed = 99
    for (mask in 1 until s.full) {
        val used = Integer.bitCount(mask)
        for (i in s.off[mask] until s.off[mask] + s.len[mask]) {
            val d = Math.abs((arena[2 * i] and LOW) - t)
            if (d < bestDistance || (d == bestDistance && used < bestUsed)) {
                best = longArrayOf(arena[2 * i], arena[2 * i + 1])
                bestDistance = d
                bestUsed = used
            }
        }
    }
    if (s.n == 1) return best
    // Check the whole pool's values as they are made since no larger subset is built from them
    var wholeHead = 0L
    var wholeOperands = 0L
    var wholeDistance = Long.MAX_VALUE
    val full = s.full
    var left = (full - 1) and full
    while (left != 0) {
        val right = full xor left
        if (left < right) {
            for (i in s.off[left] until s.off[left] + s.len[left]) {
                val a = arena[2 * i] and LOW
                for (j in s.off[right] until s.off[right] + s.len[right]) {
                    val b = arena[2 * j] and LOW
                    val x = maxOf(a, b)
                    val y = minOf(a, b)
                    val lm = if (b <= a) left else right
                    val sm = if (b <= a) right else left
                    for (k in 0 until 4) {
                        val v = when (k) {
                            0 -> x + y
                            1 -> if (x != y) x - y else 0L
                            2 -> if (y != 1L) x * y else 0L
                            else -> if (y != 1L && x % y == 0L) x / y else 0L
                        }
                        val d = Math.abs(v - t)
                        // Prefer the lower value on equal distance to break ties the same way every run
                        if (v != 0L && (d < wholeDistance || (d == wholeDistance && v < (wholeHead and LOW)))) {
                            val op = when (k) {
                                0 -> OP_ADD
                                1 -> OP_SUB
                                2 -> OP_MUL
                                else -> OP_DIV
                            }
                            wholeHead = template(op, lm, sm) or v
                            wholeOperands = x or (y shl 32)
                            wholeDistance = d
                        }
                    }
                }
            }
        }
        left = (left - 1) and full
    }
    // Fall back to the whole pool only when it gets strictly closer as it uses the most numbers
    return if (wholeDistance < bestDistance) longArrayOf(wholeHead, wholeOperands) else best
}

object Solver {
    // Return the simplest expression that hits the target or gets closest to it with its value
    fun solve(target: Int, pool: IntArray): Result {
        val n = pool.size
        val s = State(target.toLong(), n)

        // Work out each subset's largest value since subtracting and dividing never exceed the larger operand
        val largest = LongArray(n + 2)
        for (mask in 1..s.full) {
            if ((mask and (mask - 1)) == 0) {
                s.max[mask] = pool[Integer.numberOfTrailingZeros(mask)].toLong()
            } else {
                var left = (mask - 1) and mask
                while (left != 0) {
                    val a = s.max[left]
                    val b = s.max[mask xor left]
                    s.max[mask] = maxOf(s.max[mask], maxOf(a * b, a + b))
                    left = (left - 1) and mask
                }
            }
            // Track the largest value of each size so the bitset only grows when bigger subsets are built
            val size = Integer.bitCount(mask)
            largest[size] = maxOf(largest[size], s.max[mask])
        }

        // Store each pool number as a one-number subset
        var best: LongArray? = null
        for (i in 0 until n) {
            s.arena[2 * i] = pool[i].toLong()
            s.off[1 shl i] = i
            s.len[1 shl i] = 1
            if (best == null && pool[i] == target) best = longArrayOf(pool[i].toLong(), 0L)
        }
        s.top = n

        // Work through subsets smallest first stopping at the first size that hits the target
        var size = 2
        while (size <= n && best == null) {
            // Keep the lowest matching subset of this size to break ties the same way every run
            var mask = 1
            while (mask <= s.full && best == null) {
                if (Integer.bitCount(mask) == size) best = findExact(s, mask)
                mask++
            }
            // Skip building the whole pool's values since no larger subset is made from them
            if (best != null || size == n) break
            var biggest = 0
            for (m in 1..s.full) biggest = maxOf(biggest, s.len[m])
            if (biggest > s.rightValues.size) {
                s.rightValues = LongArray(biggest)
                s.rightInv = DoubleArray(biggest)
            }
            val words = (largest[size] ushr 6).toInt() + 1
            // Replace rather than copy since building leaves the bitset clear
            if (words > s.seen.size) {
                s.seen = LongArray(words)
                s.rank = IntArray(words)
            }
            for (m in 1..s.full) {
                if (Integer.bitCount(m) == size) build(s, m)
            }
            size++
        }

        val chosen = best ?: closest(s)!!
        // Render without outer brackets which matches stripping them from the bracketed form
        val expr = StringBuilder()
        render(s, chosen[0], chosen[1], false, expr)
        return Result((chosen[0] and LOW).toInt(), expr.toString())
    }
}
