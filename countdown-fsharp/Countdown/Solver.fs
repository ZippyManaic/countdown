// Work out the simplest Countdown expression that hits a target or gets closest to it
module Countdown.Solver

#nowarn "9"

open System
open System.Numerics
open System.Runtime.InteropServices
open System.Text
open Microsoft.FSharp.NativeInterop

// Sort subsets with fewer values than this by insertion rather than by rank in the bitset
[<Literal>]
let private RankMin = 16
[<Literal>]
let private OpAdd = 43UL
[<Literal>]
let private OpSub = 45UL
[<Literal>]
let private OpMul = 42UL
[<Literal>]
let private OpDiv = 47UL
[<Literal>]
let private Low = 0xFFFF_FFFFUL

// Hold the working memory of one solve in unmanaged buffers with each entry stored as a head word and an operands word
type private State =
    val Target: uint64
    val N: int
    val Full: int
    // Keep every subset's sorted values back to back in one arena
    [<DefaultValue(false)>] val mutable Arena: nativeptr<uint64>
    [<DefaultValue>] val mutable Cap: int
    [<DefaultValue>] val mutable Top: int
    val Off: int[]
    val Len: int[]
    // Hold the largest value each subset can make which bounds the bitset words it touches
    val Max: uint64[]
    // Hold one bit per value seen in the subset being built
    [<DefaultValue(false)>] val mutable Seen: nativeptr<uint64>
    [<DefaultValue>] val mutable SeenWords: int
    // Collect a subset's new values here before they are sorted into the arena
    [<DefaultValue(false)>] val mutable Tmp: nativeptr<uint64>
    [<DefaultValue>] val mutable TmpCap: int
    // Hold the count of values below each bitset word for ranking
    [<DefaultValue(false)>] val mutable Rank: nativeptr<uint32>
    // Hold the right half's values with their reciprocals for the split being built
    [<DefaultValue(false)>] val mutable RightValues: nativeptr<uint64>
    [<DefaultValue(false)>] val mutable RightInv: nativeptr<float>
    [<DefaultValue>] val mutable RightCap: int

    new(target, n) =
        { Target = target; N = n; Full = (1 <<< n) - 1
          Off = Array.zeroCreate 64; Len = Array.zeroCreate 64; Max = Array.zeroCreate 64 }

// Return a buffer of entries grown to at least need entries by doubling keeping its contents and set its capacity
let private reserve (items: nativeptr<uint64>) (cap: byref<int>) need =
    if need <= cap then items
    else
        let mutable size = max cap 1024
        while size < need do size <- size * 2
        cap <- size
        NativePtr.ofVoidPtr (NativeMemory.Realloc(NativePtr.toVoidPtr items, unativeint (size * 16)))

// Return the operator and masks of an entry shifted above its value
let inline private template (op: uint64) (largerMask: int) (smallerMask: int) =
    (op ||| (uint64 largerMask <<< 8) ||| (uint64 smallerMask <<< 16)) <<< 32

// Store a value and return the next slot which moves on only if the bitset shows the value is new
let inline private emit (seen: nativeptr<uint64>) (tmp: nativeptr<uint64>) (out: int) (v: uint64) tmpl operands =
    let word = int (v >>> 6)
    let w = NativePtr.get seen word
    NativePtr.set seen word (w ||| (1UL <<< int v))
    NativePtr.set tmp out (tmpl ||| v)
    NativePtr.set tmp (out + 1) operands
    out + (int ((~~~w >>> int v) &&& 1UL) <<< 1)

// Return x divided by y when the division is exact and zero otherwise using the reciprocal of y
let inline private exact (x: uint64) (y: uint64) (inv: float) =
    // Convert through signed integers since unsigned conversions take several instructions
    let q = uint64 (int64 (float (int64 x) * inv + 0.5))
    let miss = q * y ^^^ x
    // Turn a zero difference into an all-ones mask with arithmetic so it costs no mispredicted branch
    q &&& (((miss ||| (0UL - miss)) >>> 63) - 1UL)

// Append every new value from pairing each left value with each right value of one split and return the new end
let private emitSplit (s: State) left right start =
    let mutable out = start
    let arena = s.Arena
    let seen = s.Seen
    let tmp = s.Tmp
    let rv = s.RightValues
    let ri = s.RightInv
    let nr = s.Len[right]
    let tlAdd, tlSub = template OpAdd left right, template OpSub left right
    let tlMul, tlDiv = template OpMul left right, template OpDiv left right
    let trAdd, trSub = template OpAdd right left, template OpSub right left
    let trMul, trDiv = template OpMul right left, template OpDiv right left
    // Invert each right value once per split rather than once per pair
    let roff = s.Off[right]
    for j in 0 .. nr - 1 do
        let b = NativePtr.get arena (2 * (roff + j)) &&& Low
        NativePtr.set rv j b
        NativePtr.set ri j (1.0 / float (int64 b))
    let first = s.Off[left]
    for i in first .. first + s.Len[left] - 1 do
        let a = NativePtr.get arena (2 * i) &&& Low
        let mutable j = 0
        // Pair with right values up to a first where a is the larger and ties go left
        while j < nr && NativePtr.get rv j <= a do
            let b = NativePtr.get rv j
            let operands = a ||| (b <<< 32)
            out <- emit seen tmp out (a + b) tlAdd operands
            // Skip a zero result since every intermediate value must be a positive integer
            if a <> b then out <- emit seen tmp out (a - b) tlSub operands
            // Skip multiplying and dividing by one as they never produce a new value
            if b <> 1UL then
                out <- emit seen tmp out (a * b) tlMul operands
                out <- emit seen tmp out (exact a b (NativePtr.get ri j)) tlDiv operands
            j <- j + 1
        // Pair with the remaining larger right values where a is the smaller
        let ia = 1.0 / float (int64 a)
        while j < nr do
            let b = NativePtr.get rv j
            let operands = b ||| (a <<< 32)
            out <- emit seen tmp out (b + a) trAdd operands
            out <- emit seen tmp out (b - a) trSub operands
            if a <> 1UL then
                out <- emit seen tmp out (b * a) trMul operands
                out <- emit seen tmp out (exact b a ia) trDiv operands
            j <- j + 1
    out

// Build the sorted reachable values of a subset into the arena keeping only the first way found to make each
let private build (s: State) mask =
    let seen = s.Seen
    let mutable out = 0
    // Mark zero as seen so inexact divisions never become entries
    NativePtr.set seen 0 (NativePtr.get seen 0 ||| 1UL)
    let mutable left = (mask - 1) &&& mask
    while left <> 0 do
        let right = mask ^^^ left
        // Visit each split once rather than once per ordering
        if left < right then
            // Reserve room for every pair's results plus the one slot each store may write past the end
            let bound = int (min (4UL * uint64 s.Len[left] * uint64 s.Len[right]) s.Max[mask]) + 1
            s.Tmp <- reserve s.Tmp &s.TmpCap (out / 2 + bound)
            out <- emitSplit s left right out
        left <- (left - 1) &&& mask
    NativePtr.set seen 0 (NativePtr.get seen 0 &&& ~~~1UL)

    let count = out / 2
    let arena = reserve s.Arena &s.Cap (s.Top + count)
    s.Arena <- arena
    let tmp = s.Tmp
    let sorted = NativePtr.add arena (2 * s.Top)
    if count < RankMin then
        // Clear only the words this subset touched and insertion sort the few values
        for i in 0 .. count - 1 do
            let head = NativePtr.get tmp (2 * i)
            let operands = NativePtr.get tmp (2 * i + 1)
            let v = head &&& Low
            NativePtr.set seen (int (v >>> 6)) 0UL
            let mutable k = i
            while k > 0 && (NativePtr.get sorted (2 * k - 2) &&& Low) > v do
                NativePtr.set sorted (2 * k) (NativePtr.get sorted (2 * k - 2))
                NativePtr.set sorted (2 * k + 1) (NativePtr.get sorted (2 * k - 1))
                k <- k - 1
            NativePtr.set sorted (2 * k) head
            NativePtr.set sorted (2 * k + 1) operands
    else
        // Place each value at its rank in the bitset which needs no comparisons
        let words = int (s.Max[mask] >>> 6) + 1
        let rank = s.Rank
        let mutable below = 0u
        for w in 0 .. words - 1 do
            NativePtr.set rank w below
            below <- below + uint32 (BitOperations.PopCount(NativePtr.get seen w))
        for i in 0 .. count - 1 do
            let v = NativePtr.get tmp (2 * i) &&& Low
            let w = int (v >>> 6)
            let lower = NativePtr.get seen w &&& ((1UL <<< int v) - 1UL)
            let at = 2 * int (NativePtr.get rank w + uint32 (BitOperations.PopCount lower))
            NativePtr.set sorted at (NativePtr.get tmp (2 * i))
            NativePtr.set sorted (at + 1) (NativePtr.get tmp (2 * i + 1))
        Span<uint64>(NativePtr.toVoidPtr seen, words).Clear()
    s.Off[mask] <- s.Top
    s.Len[mask] <- count
    s.Top <- s.Top + count

// Return the arena index of value in a subset or -1 when it is absent
let inline private lookup (s: State) mask (value: uint64) =
    let arena = s.Arena
    let mutable b = s.Off[mask]
    let mutable n = s.Len[mask]
    // Skip the search when the value lies outside the subset's range
    if n = 0 || value < (NativePtr.get arena (2 * b) &&& Low) || value > (NativePtr.get arena (2 * (b + n - 1)) &&& Low) then -1
    else
        // Halve the range with a conditional move so unpredictable comparisons cost no mispredicted branch
        while n > 1 do
            let half = n >>> 1
            b <- b + (if (NativePtr.get arena (2 * (b + half)) &&& Low) <= value then half else 0)
            n <- n - half
        if (NativePtr.get arena (2 * b) &&& Low) = value then b else -1

// Return how the target is first made from a subset as a head and operands pair without building all of its values
let private findExact (s: State) mask =
    let t = s.Target
    let arena = s.Arena
    let mutable result = ValueNone
    let mutable left = (mask - 1) &&& mask
    while result.IsNone && left <> 0 do
        let right = mask ^^^ left
        // Visit splits in the same order as building so the same origin wins
        if left < right then
            let leftLoop = s.Len[left] <= s.Len[right]
            let loopMask = if leftLoop then left else right
            let searchMask = if leftLoop then right else left
            // Keep the lowest pair as building would since partners are tried in operator order
            let mutable bestA = UInt64.MaxValue
            let mutable bestB = UInt64.MaxValue
            let mutable bestOp = 0UL
            let mutable i = s.Off[loopMask]
            let stop = i + s.Len[loopMask]
            while i < stop do
                let n = NativePtr.get arena (2 * i) &&& Low
                // Bound each partner by the best so far on the searched side
                let bound = if leftLoop then bestB else bestA
                let mutable p = 0UL
                let mutable op = 0UL
                // Try each number that combines with n to make the target in operator order keeping the lowest
                if t > n && t - n < bound && lookup s searchMask (t - n) >= 0 then
                    p <- t - n
                    op <- OpAdd
                if op = 0UL && n > t && n - t < bound && lookup s searchMask (n - t) >= 0 then
                    p <- n - t
                    op <- OpSub
                if op = 0UL && n + t < bound && lookup s searchMask (n + t) >= 0 then
                    p <- n + t
                    op <- OpSub
                // Divide only when the quotient could be at least two since neither operand may be one
                if n <> 1UL && 2UL * n <= t && t % n = 0UL && t / n < (if op <> 0UL then p else bound)
                   && lookup s searchMask (t / n) >= 0 then
                    p <- t / n
                    op <- OpMul
                if n >= 2UL * t && n % t = 0UL && n / t < (if op <> 0UL then p else bound)
                   && lookup s searchMask (n / t) >= 0 then
                    p <- n / t
                    op <- OpDiv
                if n <> 1UL && n * t < (if op <> 0UL then p else bound) && lookup s searchMask (n * t) >= 0 then
                    p <- n * t
                    op <- OpDiv
                if op <> 0UL then
                    if leftLoop then
                        bestA <- n
                        bestB <- p
                        bestOp <- op
                        // Take the first left value with any partner since left values ascend
                        i <- stop
                    else
                        bestA <- p
                        bestB <- n
                        bestOp <- op
                i <- i + 1
            if bestOp <> 0UL then
                result <-
                    if bestA >= bestB then ValueSome(template bestOp left right ||| t, bestA ||| (bestB <<< 32))
                    else ValueSome(template bestOp right left ||| t, bestB ||| (bestA <<< 32))
        left <- (left - 1) &&& mask
    result

// Write the expression for an entry following its origins back to the pool with brackets when asked
let rec private render (s: State) (head: uint64) (operands: uint64) bracket (out: StringBuilder) =
    let op = (head >>> 32) &&& 255UL
    if op = 0UL then out.Append(head &&& Low) |> ignore
    else
        let larger = lookup s (int ((head >>> 40) &&& 255UL)) (operands &&& Low)
        let smaller = lookup s (int ((head >>> 48) &&& 255UL)) (operands >>> 32)
        if bracket then out.Append '(' |> ignore
        render s (NativePtr.get s.Arena (2 * larger)) (NativePtr.get s.Arena (2 * larger + 1)) true out
        out.Append(' ').Append(char op).Append(' ') |> ignore
        render s (NativePtr.get s.Arena (2 * smaller)) (NativePtr.get s.Arena (2 * smaller + 1)) true out
        if bracket then out.Append ')' |> ignore

// Make room for the values and reciprocals of the largest subset built so far
let private reserveRights (s: State) =
    let mutable biggest = 0
    for mask in 1 .. s.Full do biggest <- max biggest s.Len[mask]
    if biggest > s.RightCap then
        s.RightValues <- NativePtr.ofVoidPtr (NativeMemory.Realloc(NativePtr.toVoidPtr s.RightValues, unativeint (biggest * 8)))
        s.RightInv <- NativePtr.ofVoidPtr (NativeMemory.Realloc(NativePtr.toVoidPtr s.RightInv, unativeint (biggest * 8)))
        s.RightCap <- biggest

// Return the closest value as a head and operands pair when no subset can make the target
let private closest (s: State) =
    let arena = s.Arena
    let t = s.Target
    let inline dist (v: uint64) = if v > t then v - t else t - v
    // Rank by distance from the target then by how many numbers are used so the simplest answer wins
    let mutable best = struct (0UL, 0UL)
    let mutable bestDistance = UInt64.MaxValue
    let mutable bestUsed = 99
    for mask in 1 .. s.Full - 1 do
        let used = BitOperations.PopCount(uint32 mask)
        for i in s.Off[mask] .. s.Off[mask] + s.Len[mask] - 1 do
            let d = dist (NativePtr.get arena (2 * i) &&& Low)
            if d < bestDistance || (d = bestDistance && used < bestUsed) then
                best <- struct (NativePtr.get arena (2 * i), NativePtr.get arena (2 * i + 1))
                bestDistance <- d
                bestUsed <- used
    if s.N = 1 then best
    else
        // Check the whole pool's values as they are made since no larger subset is built from them
        let mutable wholeHead = Low
        let mutable wholeOperands = 0UL
        let mutable wholeDistance = UInt64.MaxValue
        let full = s.Full
        let mutable left = (full - 1) &&& full
        while left <> 0 do
            let right = full ^^^ left
            if left < right then
                for i in s.Off[left] .. s.Off[left] + s.Len[left] - 1 do
                    let a = NativePtr.get arena (2 * i) &&& Low
                    for j in s.Off[right] .. s.Off[right] + s.Len[right] - 1 do
                        let b = NativePtr.get arena (2 * j) &&& Low
                        let x, y = max a b, min a b
                        let lm, sm = if b <= a then left, right else right, left
                        for k in 0 .. 3 do
                            let v =
                                match k with
                                | 0 -> x + y
                                | 1 -> if x <> y then x - y else 0UL
                                | 2 -> if y <> 1UL then x * y else 0UL
                                | _ -> if y <> 1UL && x % y = 0UL then x / y else 0UL
                            let d = dist v
                            // Keep a value if it is closer to the target or equally close and lower
                            if v <> 0UL && (d < wholeDistance || (d = wholeDistance && v < (wholeHead &&& Low))) then
                                let op =
                                    match k with
                                    | 0 -> OpAdd
                                    | 1 -> OpSub
                                    | 2 -> OpMul
                                    | _ -> OpDiv
                                wholeDistance <- d
                                wholeHead <- template op lm sm ||| v
                                wholeOperands <- x ||| (y <<< 32)
            left <- (left - 1) &&& full
        // Fall back to the whole pool only when it gets strictly closer as it uses the most numbers
        if wholeDistance < bestDistance then struct (wholeHead, wholeOperands) else best

let private solveInto (s: State) (target: int) (pool: int[]) =
    let n = pool.Length
    // Work out each subset's largest value since subtracting and dividing never exceed the larger operand
    let largest: uint64[] = Array.zeroCreate (n + 2)
    for mask in 1 .. s.Full do
        if mask &&& (mask - 1) = 0 then s.Max[mask] <- uint64 pool[BitOperations.TrailingZeroCount mask]
        else
            let mutable left = (mask - 1) &&& mask
            while left <> 0 do
                let a, b = s.Max[left], s.Max[mask ^^^ left]
                s.Max[mask] <- max s.Max[mask] (max (a * b) (a + b))
                left <- (left - 1) &&& mask
        // Track the largest value of each size so the bitset only grows when bigger subsets are built
        let size = BitOperations.PopCount(uint32 mask)
        largest[size] <- max largest[size] s.Max[mask]

    // Store each pool number as a one-number subset
    s.Arena <- reserve s.Arena &s.Cap 2048
    let mutable best = ValueNone
    for i in 0 .. n - 1 do
        NativePtr.set s.Arena (2 * i) (uint64 pool[i])
        NativePtr.set s.Arena (2 * i + 1) 0UL
        s.Off[1 <<< i] <- i
        s.Len[1 <<< i] <- 1
        if best.IsNone && pool[i] = target then best <- ValueSome(uint64 pool[i], 0UL)
    s.Top <- n

    // Work through subsets smallest first stopping at the first size that hits the target
    let mutable size = 2
    while best.IsNone && size <= n do
        // Keep the lowest matching subset of this size to break ties the same way every run
        let mutable mask = 1
        while best.IsNone && mask <= s.Full do
            if BitOperations.PopCount(uint32 mask) = size then best <- findExact s mask
            mask <- mask + 1
        // Skip building the whole pool's values since no larger subset is made from them
        if best.IsNone && size < n then
            reserveRights s
            // Replace rather than copy since building leaves the bitset clear
            let words = int (largest[size] >>> 6) + 1
            if words > s.SeenWords then
                NativeMemory.Free(NativePtr.toVoidPtr s.Seen)
                NativeMemory.Free(NativePtr.toVoidPtr s.Rank)
                s.Seen <- NativePtr.ofVoidPtr (NativeMemory.AllocZeroed(unativeint words, 8un))
                s.Rank <- NativePtr.ofVoidPtr (NativeMemory.Alloc(unativeint words, 4un))
                s.SeenWords <- words
            for m in 1 .. s.Full do
                if BitOperations.PopCount(uint32 m) = size then build s m
        size <- size + 1

    let struct (head, operands) =
        match best with
        | ValueSome(h, o) -> struct (h, o)
        | ValueNone -> closest s
    // Render without outer brackets which matches stripping them from the bracketed form
    let expr = StringBuilder()
    render s head operands false expr
    int (head &&& Low), expr.ToString()

// Return the simplest expression that hits the target or gets closest to it with its value
let solve (target: int) (pool: int[]) : int * string =
    let s = State(uint64 target, pool.Length)
    try
        solveInto s target pool
    finally
        NativeMemory.Free(NativePtr.toVoidPtr s.Arena)
        NativeMemory.Free(NativePtr.toVoidPtr s.Tmp)
        NativeMemory.Free(NativePtr.toVoidPtr s.Seen)
        NativeMemory.Free(NativePtr.toVoidPtr s.Rank)
        NativeMemory.Free(NativePtr.toVoidPtr s.RightValues)
        NativeMemory.Free(NativePtr.toVoidPtr s.RightInv)
