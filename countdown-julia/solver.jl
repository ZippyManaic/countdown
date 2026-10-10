"""
Work out the simplest Countdown expression that hits a target, or the one that gets closest to it
"""
module Solver

export solve

const OP_CHARS = (UInt8('+'), UInt8('-'), UInt8('*'), UInt8('/'))

# Hold the working memory of one solve with subsets indexed by their masks
mutable struct State
    target::UInt32
    n::Int
    full::Int
    # Keep every subset's sorted values back to back in one arena
    vals::Vector{UInt32}
    top::Int
    off::Vector{Int}
    len::Vector{Int}
    # Hold the largest value each subset can make which bounds the bitset words it touches
    most::Vector{UInt64}
    # Hold one bit per value seen in the subset being built
    seen::Vector{UInt64}
    # Hold the right half's values with their reciprocals for the split being built
    rv::Vector{UInt32}
    ri::Vector{Float64}
    # Hold the partners of one value with their operators
    m::Vector{UInt32}
    op::Vector{UInt8}
end

# Choose a or b with a select marked unpredictable so LLVM keeps a conditional move instead of a branch
@inline pick(c::Bool, a::UInt32, b::UInt32) = Base.llvmcall(("""
    define i32 @entry(i8 %c, i32 %a, i32 %b) #0 {
      %t = trunc i8 %c to i1
      %r = select i1 %t, i32 %a, i32 %b, !unpredictable !0
      ret i32 %r
    }
    attributes #0 = { alwaysinline }
    !0 = !{}
    """, "entry"), UInt32, Tuple{Bool,UInt32,UInt32}, c, a, b)

@inline pick(c::Bool, a::Int, b::Int) = Base.llvmcall(("""
    define i64 @entry(i8 %c, i64 %a, i64 %b) #0 {
      %t = trunc i8 %c to i1
      %r = select i1 %t, i64 %a, i64 %b, !unpredictable !0
      ret i64 %r
    }
    attributes #0 = { alwaysinline }
    !0 = !{}
    """, "entry"), Int, Tuple{Bool,Int,Int}, c, a, b)

# Mark a value as seen with no branch so duplicates cost nothing extra
@inline function emit!(seen::Vector{UInt64}, v::UInt32)
    @inbounds seen[(v >> 6) + 1] |= one(UInt64) << (v & 0x3f)
    return nothing
end

# Return x divided by y rounded to the nearest integer by adding 1.5 * 2^52 so the low bits hold the rounded quotient
@inline quotient(x::UInt32, inv::Float64) = reinterpret(UInt64, muladd(Float64(x), inv, 6755399441055744.0)) % UInt32

# Mark every legal value from x and y under Countdown rules where x is at least y and inv is 1/y
@inline function ops!(seen::Vector{UInt64}, x::UInt32, y::UInt32, inv::Float64)
    emit!(seen, x + y)
    # Skip a zero result since every intermediate value must be a positive integer
    x != y && emit!(seen, x - y)
    # Skip multiplying and dividing by one as they never produce a new value
    if y != 0x1
        emit!(seen, x * y)
        q = quotient(x, inv)
        # Mark zero for an inexact division since zero is dropped when the values are listed
        emit!(seen, pick(q * y == x, q, zero(UInt32)))
    end
    return nothing
end

# Fill the right half's values and reciprocals for a split
@inline function load_rights!(s::State, right::Int)
    rv, ri, vals = s.rv, s.ri, s.vals
    o, nr = s.off[right], s.len[right]
    @inbounds for j in 1:nr
        v = vals[o + j]
        rv[j] = v
        ri[j] = 1.0 / Float64(v)
    end
    return nr
end

# Mark every legal combination of each left value with each right value
function pairs!(s::State, left::Int, right::Int)
    seen, rv, ri, vals = s.seen, s.rv, s.ri, s.vals
    nr = load_rights!(s, right)
    ol, nl = s.off[left], s.len[left]
    @inbounds for i in 1:nl
        a = vals[ol + i]
        j = 1
        # Take right values up to the left value first so the larger operand is known without a comparison
        while j <= nr && rv[j] <= a
            ops!(seen, a, rv[j], ri[j])
            j += 1
        end
        ia = 1.0 / Float64(a)
        while j <= nr
            ops!(seen, rv[j], a, ia)
            j += 1
        end
    end
    return nothing
end

# Return the packed distance and value of x op y whichever is closer to the target with lower values first
@inline function closer(best::UInt64, v::UInt32, t::UInt32)
    d = ifelse(v > t, v - t, t - v)
    key = (UInt64(d) << 32) | v
    # Ignore the zero an inexact division leaves
    return min(best, ifelse(v == zero(UInt32), typemax(UInt64), key))
end

# Return the closest whole-pool value packed as distance then value without storing any of them
function whole_closest(s::State)
    best = typemax(UInt64)
    t, rv, ri, vals, full = s.target, s.rv, s.ri, s.vals, s.full
    left = (full - 1) & full
    @inbounds while left != 0
        right = full ⊻ left
        if left < right
            nr = load_rights!(s, right)
            ol, nl = s.off[left], s.len[left]
            for i in 1:nl
                a = vals[ol + i]
                ia = 1.0 / Float64(a)
                for j in 1:nr
                    b = rv[j]
                    x, y, inv = ifelse(a >= b, a, b), ifelse(a >= b, b, a), ifelse(a >= b, ri[j], ia)
                    best = closer(best, x + y, t)
                    x != y && (best = closer(best, x - y, t))
                    if y != 0x1
                        best = closer(best, x * y, t)
                        q = quotient(x, inv)
                        best = closer(best, pick(q * y == x, q, zero(UInt32)), t)
                    end
                end
            end
        end
        left = (left - 1) & full
    end
    return best
end

# Build a subset's sorted values by marking every result in the bitset and listing the marked bits in order
function build!(s::State, mask::Int)
    seen = s.seen
    left = (mask - 1) & mask
    # Reserve room for every pair's results since no pair makes more than four values
    room = 0
    while left != 0
        right = mask ⊻ left
        if left < right
            room += 4 * s.len[left] * s.len[right]
            pairs!(s, left, right)
        end
        left = (left - 1) & mask
    end
    words = Int(s.most[mask] >> 6) + 1
    room = min(room, Int(s.most[mask]))
    length(s.vals) < s.top + room && resize!(s.vals, max(2 * length(s.vals), s.top + room))
    vals = s.vals
    k = s.top
    # Drop the zero that inexact divisions marked
    @inbounds seen[1] &= ~one(UInt64)
    # List each word's bits lowest first so the values come out sorted and clear the word behind
    @inbounds for w in 1:words
        x = seen[w]
        if x != 0
            base = UInt32((w - 1) << 6)
            while x != 0
                k += 1
                vals[k] = base | UInt32(trailing_zeros(x))
                x &= x - one(UInt64)
            end
            seen[w] = 0
        end
    end
    s.off[mask] = s.top
    s.len[mask] = k - s.top
    s.top = k
    return nothing
end

# Return whether value is among a subset's sorted values
@inline function contains(s::State, mask::Int, v::UInt32)
    n = s.len[mask]
    base = s.off[mask] + 1
    vals = s.vals
    @inbounds begin
        # Skip the search when the value lies outside the subset's range
        (n == 0 || v < vals[base] || v > vals[base + n - 1]) && return false
        # Halve the range with a select so unpredictable comparisons cost no mispredicted branch
        while n > 1
            half = n >> 1
            base += pick(vals[base + half] <= v, half, 0)
            n -= half
        end
        return vals[base] == v
    end
end

# Fill m and op with every number that combines with n to make t in operator order and return how many
@inline function partners!(m::Vector{UInt32}, op::Vector{UInt8}, n::UInt32, t::UInt32)
    c = 0
    @inbounds begin
        if t > n
            c += 1; m[c] = t - n; op[c] = 1
        end
        if n > t
            c += 1; m[c] = n - t; op[c] = 2
        end
        if UInt64(n) + t <= typemax(UInt32)
            c += 1; m[c] = n + t; op[c] = 2
        end
        # Divide only when the quotient could be at least two since neither operand may be one
        if n != 1 && 2 * UInt64(n) <= t && t % n == 0
            c += 1; m[c] = t ÷ n; op[c] = 3
        end
        if n >= 2 * UInt64(t) && n % t == 0
            c += 1; m[c] = n ÷ t; op[c] = 4
        end
        # Skip a product too large for any subset to make
        if n != 1 && UInt64(n) * t <= typemax(UInt32)
            c += 1; m[c] = n * t; op[c] = 4
        end
    end
    return c
end

# Return the first way building makes v from a subset as left half, left value, right value and operator
function find_way(s::State, mask::Int, v::UInt32)
    m, op, vals = s.m, s.op, s.vals
    left = (mask - 1) & mask
    @inbounds while left != 0
        right = mask ⊻ left
        # Visit splits in building order so the same way wins
        if left < right
            best_a = best_b = typemax(UInt32)
            best_op = 0x0
            if s.len[left] <= s.len[right]
                # Take the first left value with any partner on the right since left values ascend
                ol = s.off[left]
                for i in 1:s.len[left]
                    a = vals[ol + i]
                    c = partners!(m, op, a, v)
                    for k in 1:c
                        if m[k] < best_b && contains(s, right, m[k])
                            best_a, best_b, best_op = a, m[k], op[k]
                        end
                    end
                    best_op != 0 && break
                end
            else
                or = s.off[right]
                for j in 1:s.len[right]
                    b = vals[or + j]
                    c = partners!(m, op, b, v)
                    for k in 1:c
                        if m[k] < best_a && contains(s, left, m[k])
                            best_a, best_b, best_op = m[k], b, op[k]
                        end
                    end
                end
            end
            best_op != 0 && return left, best_a, best_b, best_op
        end
        left = (left - 1) & mask
    end
    return 0, zero(UInt32), zero(UInt32), 0x0
end

# Append the decimal digits of n
function put_uint!(out::Vector{UInt8}, n::UInt32)
    start = length(out)
    while true
        push!(out, UInt8('0') + UInt8(n % 10))
        n ÷= 10
        n == 0 && break
    end
    reverse!(out, start + 1, length(out))
    return out
end

# Write the expression that makes v from a subset by finding each node's first way of being made
function render!(out::Vector{UInt8}, s::State, mask::Int, v::UInt32, bracket::Bool)
    count_ones(mask) == 1 && return put_uint!(out, v)
    left, a, b, op = find_way(s, mask, v)
    right = mask ⊻ left
    larger_mask, larger, smaller_mask, smaller = a >= b ? (left, a, right, b) : (right, b, left, a)
    bracket && push!(out, UInt8('('))
    render!(out, s, larger_mask, larger, true)
    push!(out, UInt8(' '), OP_CHARS[op], UInt8(' '))
    render!(out, s, smaller_mask, smaller, true)
    bracket && push!(out, UInt8(')'))
    return out
end

# Make the bitset cover every value up to largest keeping it clear
function reserve_seen!(s::State, largest::UInt64)
    words = Int(largest >> 6) + 1
    # Replace rather than copy since building leaves the bitset clear
    words > length(s.seen) && (s.seen = zeros(UInt64, words))
    return nothing
end

# Make room for the values and reciprocals of the largest subset built so far
function reserve_rights!(s::State)
    biggest = maximum(view(s.len, 1:s.full))
    if biggest > length(s.rv)
        s.rv = Vector{UInt32}(undef, 2 * biggest)
        s.ri = Vector{Float64}(undef, 2 * biggest)
    end
    return nothing
end

# Return the simplest expression that hits the target or gets closest to it, with its value
function solve(target::Integer, pool::AbstractVector{<:Integer})
    n = length(pool)
    1 <= n <= 6 || throw(ArgumentError("pool must hold one to six numbers"))
    # Keep every value below 2^32 so 32-bit arithmetic never wraps
    prod(UInt64(p) + 1 for p in pool) < UInt64(1) << 32 || throw(ArgumentError("pool numbers too large"))
    full = (1 << n) - 1
    t = UInt32(target)
    s = State(t, n, full, Vector{UInt32}(undef, 256), n, zeros(Int, 64), zeros(Int, 64), zeros(UInt64, 64),
              zeros(UInt64, 1), Vector{UInt32}(undef, 64), Vector{Float64}(undef, 64),
              Vector{UInt32}(undef, 6), Vector{UInt8}(undef, 6))

    # Work out each subset's largest value since subtracting and dividing never exceed the larger operand
    largest = zeros(UInt64, n)
    for mask in 1:full
        if count_ones(mask) == 1
            s.most[mask] = UInt64(pool[trailing_zeros(mask) + 1])
        else
            left = (mask - 1) & mask
            while left != 0
                a, b = s.most[left], s.most[mask ⊻ left]
                s.most[mask] = max(s.most[mask], a * b, a + b)
                left = (left - 1) & mask
            end
        end
        size = count_ones(mask)
        largest[size] = max(largest[size], s.most[mask])
    end

    # Store each pool number as a one-number subset
    for i in 1:n
        s.vals[i] = UInt32(pool[i])
        s.off[1 << (i - 1)] = i - 1
        s.len[1 << (i - 1)] = 1
    end
    i = findfirst(==(target), pool)
    hit = i === nothing ? 0 : 1 << (i - 1)

    # List subsets by size then mask
    order = sort!(collect(1:full); by = m -> (count_ones(m), m))

    # Work through subsets smallest first stopping at the first size that hits the target
    size = 2
    while hit == 0 && size <= n
        for mask in order
            count_ones(mask) == size || continue
            if find_way(s, mask, t)[4] != 0
                hit = mask
                break
            end
        end
        # Skip building the whole pool's values since no larger subset is made from them
        (hit != 0 || size == n) && break
        reserve_rights!(s)
        reserve_seen!(s, largest[size])
        for mask in order
            count_ones(mask) == size && build!(s, mask)
        end
        size += 1
    end

    out = sizehint!(UInt8[], 64)
    if hit != 0
        render!(out, s, hit, t, false)
        return Int(t), String(out)
    end

    # Rank by distance from the target then by how many numbers are used so the simplest answer wins
    best_mask, best_value, best_distance, best_used = 0, zero(UInt32), typemax(UInt32), typemax(Int)
    for mask in 1:full-1
        o, len = s.off[mask], s.len[mask]
        vals = view(s.vals, o+1:o+len)
        # Look only beside the target since the values ascend and lower values win ties
        k = searchsortedfirst(vals, t)
        v, d = zero(UInt32), typemax(UInt32)
        if k <= len
            v, d = vals[k], vals[k] - t
        end
        if k > 1 && t - vals[k - 1] <= d
            v, d = vals[k - 1], t - vals[k - 1]
        end
        used = count_ones(mask)
        if d < best_distance || (d == best_distance && used < best_used)
            best_mask, best_value, best_distance, best_used = mask, v, d, used
        end
    end
    # Fall back to the whole pool only when it gets strictly closer as it uses the most numbers
    if n > 1
        reserve_rights!(s)
        key = whole_closest(s)
        if UInt32(key >> 32) < best_distance
            best_mask, best_value = full, UInt32(key & 0xffffffff)
        end
    else
        best_mask, best_value = 1, UInt32(pool[1])
    end
    render!(out, s, best_mask, best_value, false)
    return Int(best_value), String(out)
end

end
