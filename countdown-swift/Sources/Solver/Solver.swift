// Work out the simplest Countdown expression that hits a target or gets closest to it

// Sort subsets with fewer values than this by insertion rather than by rank in the bitset
private let rankMin = 16
private let opAdd: UInt64 = 43
private let opSub: UInt64 = 45
private let opMul: UInt64 = 42
private let opDiv: UInt64 = 47
private let low: UInt64 = 0xFFFF_FFFF

// Record a reachable value with how it was made from the larger and smaller of two values in disjoint subsets
private struct Entry {
    // Pack value, operator (zero for a pool number), larger mask and smaller mask from the low bits up
    var head: UInt64
    // Pack the larger operand in the low half and the smaller in the high half
    var operands: UInt64

    @inline(__always) var value: UInt64 { head & low }
}

// Return the operator and masks of an entry shifted above its value
@inline(__always)
private func template(_ op: UInt64, _ largerMask: Int, _ smallerMask: Int) -> UInt64 {
    (op | UInt64(largerMask) << 8 | UInt64(smallerMask) << 16) << 32
}

// Own an uninitialised buffer that grows by doubling and keeps a prefix of its contents
private struct Buffer<T> {
    var base: UnsafeMutablePointer<T>
    var capacity: Int

    init(capacity: Int) {
        self.capacity = capacity
        base = .allocate(capacity: capacity)
    }

    mutating func reserve(_ need: Int, keeping keep: Int) {
        if need <= capacity { return }
        var size = max(capacity, 1024)
        while size < need { size *= 2 }
        let grown = UnsafeMutablePointer<T>.allocate(capacity: size)
        grown.moveInitialize(from: base, count: keep)
        base.deallocate()
        base = grown
        capacity = size
    }

    func free() { base.deallocate() }
}

// Hold the working memory of one solve
private struct State {
    let target: UInt64
    let n: Int
    let full: Int
    // Keep every subset's sorted values back to back in one arena
    var arena = Buffer<Entry>(capacity: 4096)
    var top = 0
    // Keep per-subset tables in raw memory so lookups need no bounds checks
    let off: UnsafeMutablePointer<Int>
    let len: UnsafeMutablePointer<Int>
    // Hold the largest value each subset can make which bounds the bitset words it touches
    let max: UnsafeMutablePointer<UInt64>
    // Hold one bit per value seen in the subset being built
    var seen = Buffer<UInt64>(capacity: 1)
    var seenWords = 0
    // Collect a subset's new values here before they are sorted into the arena
    var tmp = Buffer<Entry>(capacity: 4096)
    // Hold the count of values below each bitset word for ranking
    var rank = Buffer<UInt32>(capacity: 1)
    // Hold the right half's values with their reciprocals for the split being built
    var rightValues = Buffer<UInt64>(capacity: 1)
    var rightInv = Buffer<Double>(capacity: 1)

    init(target: Int, n: Int) {
        self.target = UInt64(target)
        self.n = n
        full = (1 << n) - 1
        off = .allocate(capacity: full + 1)
        off.initialize(repeating: 0, count: full + 1)
        len = .allocate(capacity: full + 1)
        len.initialize(repeating: 0, count: full + 1)
        max = .allocate(capacity: full + 1)
        max.initialize(repeating: 0, count: full + 1)
    }

    func free() {
        off.deallocate()
        len.deallocate()
        max.deallocate()
        arena.free()
        seen.free()
        tmp.free()
        rank.free()
        rightValues.free()
        rightInv.free()
    }
}

// Store a value and return the next slot which moves on only if the bitset shows the value is new
@inline(__always)
private func emit(_ seen: UnsafeMutablePointer<UInt64>, _ output: UnsafeMutablePointer<Entry>, _ v: UInt64,
                  _ tmpl: UInt64, _ operands: UInt64) -> UnsafeMutablePointer<Entry> {
    let word = Int(truncatingIfNeeded: v >> 6)
    let w = seen[word]
    seen[word] = w | 1 &<< (v & 63)
    output.pointee = Entry(head: tmpl | v, operands: operands)
    return output + Int(truncatingIfNeeded: ~w &>> (v & 63) & 1)
}

// Return x divided by y when the division is exact and zero otherwise using the reciprocal of y
@inline(__always)
private func exact(_ x: UInt64, _ y: UInt64, _ inv: Double) -> UInt64 {
    let q = UInt64(Double(x) * inv + 0.5)
    // Turn a zero difference into an all-ones mask with arithmetic since Swift compiles the comparison to a branch
    return q & (0 &- (((q &* y) ^ x) &- 1) >> 63)
}

// Append every new value from pairing each left value with each right value of one split and return the new end
private func emitSplit(_ s: inout State, _ left: Int, _ right: Int, _ start: UnsafeMutablePointer<Entry>)
    -> UnsafeMutablePointer<Entry> {
    let seen = s.seen.base
    let rv = s.rightValues.base
    let ri = s.rightInv.base
    let lefts = s.arena.base + s.off[left]
    let rights = s.arena.base + s.off[right]
    let nl = s.len[left]
    let nr = s.len[right]
    let tlAdd = template(opAdd, left, right), tlSub = template(opSub, left, right)
    let tlMul = template(opMul, left, right), tlDiv = template(opDiv, left, right)
    let trAdd = template(opAdd, right, left), trSub = template(opSub, right, left)
    let trMul = template(opMul, right, left), trDiv = template(opDiv, right, left)
    var output = start
    // Invert each right value once per split rather than once per pair
    for j in 0..<nr {
        rv[j] = rights[j].value
        ri[j] = 1.0 / Double(rv[j])
    }
    for i in 0..<nl {
        let a = lefts[i].value
        var j = 0
        // Pair with right values up to a first where a is the larger and ties go left
        while j < nr && rv[j] <= a {
            let b = rv[j]
            let operands = a | b << 32
            output = emit(seen, output, a &+ b, tlAdd, operands)
            // Skip a zero result since every intermediate value must be a positive integer
            if a != b { output = emit(seen, output, a &- b, tlSub, operands) }
            // Skip multiplying and dividing by one as they never produce a new value
            if b != 1 {
                output = emit(seen, output, a &* b, tlMul, operands)
                output = emit(seen, output, exact(a, b, ri[j]), tlDiv, operands)
            }
            j &+= 1
        }
        // Pair with the remaining larger right values where a is the smaller
        let ia = 1.0 / Double(a)
        while j < nr {
            let b = rv[j]
            let operands = b | a << 32
            output = emit(seen, output, b &+ a, trAdd, operands)
            output = emit(seen, output, b &- a, trSub, operands)
            if a != 1 {
                output = emit(seen, output, b &* a, trMul, operands)
                output = emit(seen, output, exact(b, a, ia), trDiv, operands)
            }
            j &+= 1
        }
    }
    return output
}

// Build the sorted reachable values of a subset into the arena keeping only the first way found to make each
private func build(_ s: inout State, _ mask: Int) {
    let seen = s.seen.base
    var count = 0
    // Mark zero as seen so inexact divisions never become entries
    seen[0] |= 1
    var left = (mask - 1) & mask
    while left != 0 {
        let right = mask ^ left
        // Visit each split once rather than once per ordering
        if left < right {
            // Reserve room for every pair's results plus the one slot each store may write past the end
            let bound = Int(min(4 * UInt64(s.len[left]) * UInt64(s.len[right]), s.max[mask])) + 1
            s.tmp.reserve(count + bound, keeping: count)
            count = emitSplit(&s, left, right, s.tmp.base + count) - s.tmp.base
        }
        left = (left - 1) & mask
    }
    seen[0] &= ~1

    s.arena.reserve(s.top + count, keeping: s.top)
    let sorted = s.arena.base + s.top
    let tmp = s.tmp.base
    if count < rankMin {
        // Clear only the words this subset touched and insertion sort the few values
        for i in 0..<count {
            let e = tmp[i]
            seen[Int(e.value >> 6)] = 0
            var k = i
            while k > 0 && sorted[k - 1].value > e.value {
                sorted[k] = sorted[k - 1]
                k -= 1
            }
            sorted[k] = e
        }
    } else {
        // Place each value at its rank in the bitset which needs no comparisons
        let words = Int(s.max[mask] >> 6) + 1
        let rank = s.rank.base
        var below: UInt32 = 0
        for w in 0..<words {
            rank[w] = below
            below &+= UInt32(truncatingIfNeeded: seen[w].nonzeroBitCount)
        }
        for i in 0..<count {
            let v = tmp[i].value
            let w = Int(v >> 6)
            let lower = seen[w] & ((1 &<< (v & 63)) &- 1)
            sorted[Int(rank[w]) + lower.nonzeroBitCount] = tmp[i]
        }
        seen.update(repeating: 0, count: words)
    }
    s.off[mask] = s.top
    s.len[mask] = count
    s.top += count
}

// Return the arena index of value in a subset or nil when it is absent
@inline(__always)
private func lookup(_ s: State, _ mask: Int, _ value: UInt64) -> Int? {
    let arena = s.arena.base
    var base = s.off[mask]
    var n = s.len[mask]
    // Skip the search when the value lies outside the subset's range
    if n == 0 || value < arena[base].value || value > arena[base + n - 1].value { return nil }
    // Halve the range without branching so unpredictable comparisons cost no mispredicted branch
    while n > 1 {
        let half = n >> 1
        // Build an all-ones mask when the middle value is at most the one sought since a ternary becomes a branch
        base &+= half & Int(truncatingIfNeeded: (value &- arena[base + half].value) >> 63 &- 1)
        n &-= half
    }
    return arena[base].value == value ? base : nil
}

// Return how the target is first made from a subset without building all of its values
private func findExact(_ s: State, _ mask: Int) -> Entry? {
    let t = s.target
    let arena = s.arena.base
    var left = (mask - 1) & mask
    while left != 0 {
        let right = mask ^ left
        // Visit splits in the same order as building so the same origin wins
        if left < right {
            let leftLoop = s.len[left] <= s.len[right]
            let loopMask = leftLoop ? left : right
            let searchMask = leftLoop ? right : left
            // Keep the lowest pair as building would since partners are tried in operator order
            var bestA = UInt64.max, bestB = UInt64.max, bestOp: UInt64 = 0

            // Keep a partner when it beats the best so far and the searched subset can make it
            func attempt(_ n: UInt64, _ m: UInt64, _ op: UInt64) {
                if leftLoop {
                    if m < bestB && lookup(s, searchMask, m) != nil { bestA = n; bestB = m; bestOp = op }
                } else if m < bestA && lookup(s, searchMask, m) != nil {
                    bestA = m; bestB = n; bestOp = op
                }
            }

            for i in s.off[loopMask]..<(s.off[loopMask] + s.len[loopMask]) {
                let n = arena[i].value
                // Try each number that combines with n to make the target in operator order
                if t > n { attempt(n, t - n, opAdd) }
                if n > t { attempt(n, n - t, opSub) }
                attempt(n, n + t, opSub)
                // Divide only when the quotient could be at least two since neither operand may be one
                if n != 1 && 2 * n <= t && t % n == 0 { attempt(n, t / n, opMul) }
                if n >= 2 * t && n % t == 0 { attempt(n, n / t, opDiv) }
                if n != 1 { attempt(n, n * t, opDiv) }
                // Take the first left value with any partner since left values ascend
                if bestOp != 0 && leftLoop { break }
            }
            if bestOp != 0 {
                return bestA >= bestB
                    ? Entry(head: template(bestOp, left, right) | t, operands: bestA | bestB << 32)
                    : Entry(head: template(bestOp, right, left) | t, operands: bestB | bestA << 32)
            }
        }
        left = (left - 1) & mask
    }
    return nil
}

// Write the expression for an entry following its origins back to the pool with brackets when asked
private func render(_ s: State, _ e: Entry, _ bracket: Bool) -> String {
    let op = e.head >> 32 & 255
    if op == 0 { return String(e.value) }
    let larger = s.arena.base[lookup(s, Int(e.head >> 40 & 255), e.operands & low)!]
    let smaller = s.arena.base[lookup(s, Int(e.head >> 48 & 255), e.operands >> 32)!]
    let text = "\(render(s, larger, true)) \(Character(Unicode.Scalar(UInt8(op)))) \(render(s, smaller, true))"
    return bracket ? "(\(text))" : text
}

// Make room for the values and reciprocals of the largest subset built so far
private func reserveRights(_ s: inout State) {
    var biggest = 0
    for mask in 0...s.full { biggest = Swift.max(biggest, s.len[mask]) }
    s.rightValues.reserve(biggest, keeping: 0)
    s.rightInv.reserve(biggest, keeping: 0)
}

// Return the closest value when no subset can make the target
private func closest(_ s: inout State) -> Entry {
    let t = s.target
    let arena = s.arena.base
    func distance(_ v: UInt64) -> UInt64 { v > t ? v - t : t - v }
    // Rank by distance from the target then by how many numbers are used so the simplest answer wins
    var best = Entry(head: 0, operands: 0)
    var bestDistance = UInt64.max
    var bestUsed = 99
    for mask in 1..<s.full {
        let used = mask.nonzeroBitCount
        for i in s.off[mask]..<(s.off[mask] + s.len[mask]) {
            let d = distance(arena[i].value)
            if d < bestDistance || (d == bestDistance && used < bestUsed) {
                best = arena[i]
                bestDistance = d
                bestUsed = used
            }
        }
    }
    if s.n == 1 { return best }
    // Check the whole pool's values as they are made since no larger subset is built from them
    var whole = Entry(head: low, operands: 0)
    var wholeDistance = UInt64.max
    var left = (s.full - 1) & s.full
    while left != 0 {
        let right = s.full ^ left
        if left < right {
            for i in s.off[left]..<(s.off[left] + s.len[left]) {
                for j in s.off[right]..<(s.off[right] + s.len[right]) {
                    let a = arena[i].value, b = arena[j].value
                    let x = Swift.max(a, b), y = Swift.min(a, b)
                    let lm = b <= a ? left : right, sm = b <= a ? right : left
                    let operands = x | y << 32

                    // Keep a value if it is closer to the target or equally close and lower
                    func check(_ v: UInt64, _ op: UInt64) {
                        let d = distance(v)
                        if d < wholeDistance || (d == wholeDistance && v < whole.value) {
                            wholeDistance = d
                            whole = Entry(head: template(op, lm, sm) | v, operands: operands)
                        }
                    }

                    check(x + y, opAdd)
                    if x != y { check(x - y, opSub) }
                    if y != 1 {
                        check(x * y, opMul)
                        if x % y == 0 { check(x / y, opDiv) }
                    }
                }
            }
        }
        left = (left - 1) & s.full
    }
    // Fall back to the whole pool only when it gets strictly closer as it uses the most numbers
    return wholeDistance < bestDistance ? whole : best
}

// Return the simplest expression that hits the target or gets closest to it with its value
public func solve(target: Int, pool: [Int]) -> (value: Int, expr: String) {
    var s = State(target: target, n: pool.count)
    defer { s.free() }
    let n = pool.count

    // Work out each subset's largest value since subtracting and dividing never exceed the larger operand
    var largest = [UInt64](repeating: 0, count: n + 2)
    for mask in 1...s.full {
        if mask & (mask - 1) == 0 {
            s.max[mask] = UInt64(pool[mask.trailingZeroBitCount])
        } else {
            var left = (mask - 1) & mask
            while left != 0 {
                let a = s.max[left], b = s.max[mask ^ left]
                s.max[mask] = max(s.max[mask], a * b, a + b)
                left = (left - 1) & mask
            }
        }
        // Track the largest value of each size so the bitset only grows when bigger subsets are built
        largest[mask.nonzeroBitCount] = max(largest[mask.nonzeroBitCount], s.max[mask])
    }

    // Store each pool number as a one-number subset
    var best: Entry?
    for i in 0..<n {
        s.arena.base[i] = Entry(head: UInt64(pool[i]), operands: 0)
        s.off[1 << i] = i
        s.len[1 << i] = 1
        if best == nil && pool[i] == target { best = s.arena.base[i] }
    }
    s.top = n

    // Work through subsets smallest first stopping at the first size that hits the target
    var size = 2
    while size <= n && best == nil {
        // Keep the lowest matching subset of this size to break ties the same way every run
        for mask in 1...s.full where mask.nonzeroBitCount == size {
            best = findExact(s, mask)
            if best != nil { break }
        }
        // Skip building the whole pool's values since no larger subset is made from them
        if best != nil || size == n { break }
        reserveRights(&s)
        // Replace rather than copy since building leaves the bitset clear
        let words = Int(largest[size] >> 6) + 1
        if words > s.seenWords {
            s.seen.free()
            s.rank.free()
            s.seen = Buffer(capacity: words)
            s.seen.base.initialize(repeating: 0, count: words)
            s.rank = Buffer(capacity: words)
            s.seenWords = words
        }
        for mask in 1...s.full where mask.nonzeroBitCount == size {
            build(&s, mask)
        }
        size += 1
    }

    if best == nil {
        reserveRights(&s)
        best = closest(&s)
    }

    // Render without outer brackets which matches stripping them from the bracketed form
    return (Int(best!.value), render(s, best!, false))
}
