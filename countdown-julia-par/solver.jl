"""
Work out the simplest Countdown expression that hits a target, or the one that gets closest to it, with several
threads sharing the work of each round
"""
module ParSolver

export solve, threads

const OP_CHARS = (UInt8('+'), UInt8('-'), UInt8('*'), UInt8('/'))
# List and radix sort a subset's values when its bitset has more than this many words per value it could make
const SPARSE = 64

# Name the kinds of work a job can hand out
const BUILD = 1
const SEARCH = 2
const WHOLE = 3

# Read a tuning setting from the environment falling back to a default
setting(name, default) = parse(Int, get(ENV, name, string(default)))

# Share a level's builds only when it forms at least this many pairs
const BUILD_MIN = setting("COUNTDOWN_BUILD_MIN", 400)
# Share searches only for subsets of at least this size which by default is never since sharing them lost
const SEARCH_SIZE = setting("COUNTDOWN_SEARCH_SIZE", 99)
# Share the whole-pool closest pass only when it forms at least this many pairs
const WHOLE_MIN = setting("COUNTDOWN_WHOLE_MIN", 2000)

# Hold one atomic word alone on its cache lines so threads polling it never disturb its neighbours
mutable struct Padded
    @atomic v::UInt64
    pad::NTuple{15,UInt64}
end
Padded(v) = Padded(UInt64(v), ntuple(_ -> zero(UInt64), 15))

# Hold one thread's private buffers for a solve
mutable struct Scratch
    # Point at one bit per value seen in the subset being built allocated outside the garbage collector
    seen::Ptr{UInt64}
    words::Int
    # Collect a sparse subset's new values here before they are sorted into the arena
    tmp::Vector{UInt32}
    # Hold the right half's values with their reciprocals for the split being worked on
    rv::Vector{UInt32}
    ri::Vector{Float64}
    # Hold the partners of one value with their operators
    m::Vector{UInt32}
    op::Vector{UInt8}
end
Scratch() = Scratch(Ptr{UInt64}(0), 0, Vector{UInt32}(undef, 0), Vector{UInt32}(undef, 64), Vector{Float64}(undef, 64),
                    Vector{UInt32}(undef, 6), Vector{UInt8}(undef, 6))

# Hold the working memory of one solve with subsets indexed by their masks
mutable struct State
    target::UInt32
    n::Int
    full::Int
    # Keep every subset's sorted values in its own region of one arena
    vals::Vector{UInt32}
    top::Int
    off::Vector{Int}
    len::Vector{Int}
    # Hold the largest value each subset can make which bounds the bitset words it touches
    most::Vector{UInt64}
    # Hold the largest value any subset of the level being built can make
    level_most::UInt64
    scratch::Vector{Scratch}
    # Hold the lowest search item that hits the target
    @atomic found::UInt64
    # Hold the closest whole-pool value packed as distance then value
    @atomic nearest::UInt64
end

# Describe one batch of work items handed to every thread
mutable struct Job
    kind::Int
    state::Union{State,Nothing}
    # Hold each item's subset mask and for searches its left half
    masks::Vector{Int}
    lefts::Vector{Int}
end
Job() = Job(0, nothing, Int[], Int[])

# Hold the persistent worker threads which carry no round data between jobs
mutable struct Pool
    threads::Int
    spawn::Bool
    # Pack the generation above the item count above the next unclaimed item
    ticket::Padded
    done::Padded
    gen::Int
    jobs::NTuple{2,Job}
    lock::Threads.SpinLock
    # Hold the first error an item raised so the caller can rethrow it instead of waiting forever
    error::Any
    # Tell workers to return so the process can exit
    @atomic stop::Bool
end

const POOL = Ref{Union{Pool,Nothing}}(nothing)

# List every pool size's subsets by size then mask once since they depend only on the pool size
const MASKS = [[[m for m in 1:(1 << n) - 1 if count_ones(m) == k] for k in 1:n] for n in 1:6]

# Count the CPUs this process may run on so spinning threads never outnumber them
function allowed_cpus()
    for line in eachline("/proc/self/status")
        startswith(line, "Cpus_allowed_list:") || continue
        total = 0
        for part in split(strip(split(line, ':')[2]), ',')
            bounds = parse.(Int, split(part, '-'))
            total += bounds[end] - bounds[1] + 1
        end
        return total
    end
    return Sys.CPU_THREADS
end

const THREADS = Ref(0)

# Return how many threads solves share their work across working it out once since it needs a file read
function threads()
    if THREADS[] == 0
        THREADS[] = max(1, min(setting("COUNTDOWN_THREADS", 8), Threads.maxthreadid(), allowed_cpus()))
    end
    return THREADS[]
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
@inline function emit!(seen::Ptr{UInt64}, v::UInt32)
    p = seen + 8 * (v >> 6)
    unsafe_store!(p, unsafe_load(p) | (one(UInt64) << (v & 0x3f)))
    return nothing
end

# Return x divided by y rounded to the nearest integer by adding 1.5 * 2^52 so the low bits hold the rounded quotient
@inline quotient(x::UInt32, inv::Float64) = reinterpret(UInt64, muladd(Float64(x), inv, 6755399441055744.0)) % UInt32

# Mark every legal value from x and y under Countdown rules where x is at least y and inv is 1/y
@inline function ops!(seen::Ptr{UInt64}, x::UInt32, y::UInt32, inv::Float64)
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

# Mark a value as seen and append it to tmp advancing past it only if it is new
@inline function emit!(seen::Ptr{UInt64}, tmp::Vector{UInt32}, k::Int, v::UInt32)
    p = seen + 8 * (v >> 6)
    w = unsafe_load(p)
    unsafe_store!(p, w | (one(UInt64) << (v & 0x3f)))
    @inbounds tmp[k + 1] = v
    return k + 1 - Int((w >> (v & 0x3f)) & one(UInt64))
end

# Append every new legal value from x and y to tmp where x is at least y and inv is 1/y and return the new count
@inline function ops!(seen::Ptr{UInt64}, tmp::Vector{UInt32}, k::Int, x::UInt32, y::UInt32, inv::Float64)
    k = emit!(seen, tmp, k, x + y)
    x != y && (k = emit!(seen, tmp, k, x - y))
    if y != 0x1
        k = emit!(seen, tmp, k, x * y)
        q = quotient(x, inv)
        # Emit zero for an inexact division since zero is already marked and never appended
        k = emit!(seen, tmp, k, pick(q * y == x, q, zero(UInt32)))
    end
    return k
end

# Fill the right half's values and reciprocals for a split
@inline function load_rights!(sc::Scratch, s::State, right::Int)
    rv, ri, vals = sc.rv, sc.ri, s.vals
    o, nr = s.off[right], s.len[right]
    @inbounds for j in 1:nr
        v = vals[o + j]
        rv[j] = v
        ri[j] = 1.0 / Float64(v)
    end
    return nr
end

# Mark every legal combination of each left value with each right value
function pairs!(sc::Scratch, s::State, left::Int, right::Int)
    seen, rv, ri, vals = sc.seen, sc.rv, sc.ri, s.vals
    nr = load_rights!(sc, s, right)
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

# Append every new combination of each left value with each right value to tmp and return the new count
function pairs!(sc::Scratch, s::State, left::Int, right::Int, k::Int)
    seen, tmp, rv, ri, vals = sc.seen, sc.tmp, sc.rv, sc.ri, s.vals
    nr = load_rights!(sc, s, right)
    ol, nl = s.off[left], s.len[left]
    @inbounds for i in 1:nl
        a = vals[ol + i]
        j = 1
        while j <= nr && rv[j] <= a
            k = ops!(seen, tmp, k, a, rv[j], ri[j])
            j += 1
        end
        ia = 1.0 / Float64(a)
        while j <= nr
            k = ops!(seen, tmp, k, rv[j], a, ia)
            j += 1
        end
    end
    return k
end

# Radix sort a sparse subset's listed values into its arena region in three 11-bit passes and clear the words they touched
function radix!(sc::Scratch, s::State, mask::Int, count::Int)
    seen, tmp, vals, top = sc.seen, sc.tmp, s.vals, s.off[mask]
    counts = zeros(UInt32, 2048, 3)
    @inbounds for i in 1:count
        v = tmp[i]
        unsafe_store!(seen, zero(UInt64), (v >> 6) + 1)
        counts[(v & 0x7ff) + 1, 1] += 1
        counts[((v >> 11) & 0x7ff) + 1, 2] += 1
        counts[(v >> 22) + 1, 3] += 1
    end
    # Pass from tmp to the arena and back so the third pass lands in the arena
    from, from_at, to, to_at = tmp, 0, vals, top
    @inbounds for pass in 1:3
        sum = zero(UInt32)
        for d in 1:2048
            c = counts[d, pass]
            counts[d, pass] = sum
            sum += c
        end
        shift = 11 * (pass - 1)
        for i in 1:count
            v = from[from_at + i]
            d = ((v >> shift) & 0x7ff) + 1
            at = counts[d, pass]
            counts[d, pass] = at + one(UInt32)
            to[to_at + Int(at) + 1] = v
        end
        from, from_at, to, to_at = to, to_at, from, from_at
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

# Return the closest value one split of the whole pool makes packed as distance then value
function whole_split(sc::Scratch, s::State, left::Int)
    best = typemax(UInt64)
    t, rv, ri, vals = s.target, sc.rv, sc.ri, s.vals
    nr = load_rights!(sc, s, s.full ⊻ left)
    ol, nl = s.off[left], s.len[left]
    @inbounds for i in 1:nl
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
    return best
end

# Make this thread's bitset cover every value up to largest keeping it clear
function reserve_seen!(sc::Scratch, largest::UInt64)
    words = Int(largest >> 6) + 1
    if words > sc.words
        # Replace rather than copy since building leaves the bitset clear
        sc.seen == C_NULL || Libc.free(sc.seen)
        sc.seen = Ptr{UInt64}(Libc.calloc(words, 8))
        sc.seen == C_NULL && throw(OutOfMemoryError())
        sc.words = words
    end
    return nothing
end

# Build a subset's sorted values into the arena region reserved for it
function build!(sc::Scratch, s::State, mask::Int)
    reserve_seen!(sc, s.level_most)
    seen = sc.seen
    words = Int(s.most[mask] >> 6) + 1
    room = 0
    left = (mask - 1) & mask
    while left != 0
        right = mask ⊻ left
        left < right && (room += 4 * s.len[left] * s.len[right])
        left = (left - 1) & mask
    end
    if words > SPARSE * room
        # List the values of a subset too sparse to scan so the cost follows the values rather than the range
        length(sc.tmp) < room + 1 && (sc.tmp = Vector{UInt32}(undef, max(2 * length(sc.tmp), room + 1)))
        # Mark zero as seen so inexact divisions never become values
        unsafe_store!(seen, unsafe_load(seen) | one(UInt64))
        count = 0
        left = (mask - 1) & mask
        while left != 0
            right = mask ⊻ left
            left < right && (count = pairs!(sc, s, left, right, count))
            left = (left - 1) & mask
        end
        radix!(sc, s, mask, count)
        unsafe_store!(seen, unsafe_load(seen) & ~one(UInt64))
        s.len[mask] = count
        return nothing
    end
    left = (mask - 1) & mask
    while left != 0
        right = mask ⊻ left
        left < right && pairs!(sc, s, left, right)
        left = (left - 1) & mask
    end
    vals = s.vals
    k = s.off[mask]
    # Drop the zero that inexact divisions marked
    unsafe_store!(seen, unsafe_load(seen) & ~one(UInt64))
    # List each word's bits lowest first so the values come out sorted and clear the word behind
    @inbounds for w in 1:words
        x = unsafe_load(seen, w)
        if x != 0
            base = UInt32((w - 1) << 6)
            while x != 0
                k += 1
                vals[k] = base | UInt32(trailing_zeros(x))
                x &= x - one(UInt64)
            end
            unsafe_store!(seen, zero(UInt64), w)
        end
    end
    s.len[mask] = k - s.off[mask]
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

# Return the first way one split makes v as left value, right value and operator with a zero operator for none
function split_way(m::Vector{UInt32}, op::Vector{UInt8}, s::State, left::Int, right::Int, v::UInt32)
    vals = s.vals
    best_a = best_b = typemax(UInt32)
    best_op = 0x0
    @inbounds if s.len[left] <= s.len[right]
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
    return best_a, best_b, best_op
end

# Return the first way building makes v from a subset as left half, left value, right value and operator
function find_way(sc::Scratch, s::State, mask::Int, v::UInt32)
    left = (mask - 1) & mask
    while left != 0
        right = mask ⊻ left
        # Visit splits in building order so the same way wins
        if left < right
            a, b, op = split_way(sc.m, sc.op, s, left, right, v)
            op != 0 && return left, a, b, op
        end
        left = (left - 1) & mask
    end
    return 0, zero(UInt32), zero(UInt32), 0x0
end

# Do one item of a job on behalf of thread id
function run_item!(job::Job, i::Int, id::Int)
    s = job.state::State
    sc = s.scratch[id]
    kind = job.kind
    if kind == BUILD
        build!(sc, s, @inbounds job.masks[i])
    elseif kind == SEARCH
        # Skip items after one already known to hit since the earliest hit wins
        if UInt64(i) < (@atomic :monotonic s.found)
            mask, left = @inbounds job.masks[i], job.lefts[i]
            if split_way(sc.m, sc.op, s, left, mask ⊻ left, s.target)[3] != 0
                @atomic :acquire_release s.found min UInt64(i)
            end
        end
    else
        key = whole_split(sc, s, @inbounds job.lefts[i])
        @atomic :acquire_release s.nearest min key
    end
    return nothing
end

# Claim and run the current job's items until none are left and return how many this thread ran
function claim!(pool::Pool, id::Int)
    while true
        t = @atomic :acquire pool.ticket.v
        next, count = Int(t & 0xfffff), Int((t >> 20) & 0xfffff)
        next >= count && return nothing
        # Claim the item only if the ticket still names this job and item
        _, ok = @atomicreplace :acquire_release :monotonic pool.ticket.v t => t + 1
        ok || continue
        # Read the job only after claiming since its slot cannot be reused until this item is done
        try
            run_item!(@inbounds(pool.jobs[Int(t >> 40) & 1 + 1]), next + 1, id)
        catch e
            pool.error === nothing && (pool.error = e)
        end
        @atomic :release pool.done.v += one(UInt64)
    end
end

# Spin waiting for jobs on a worker thread pausing politely and sleeping only after a long idle spell
function work(pool::Pool, id::Int)
    idle = 0
    while !(@atomic :monotonic pool.stop)
        t = @atomic :acquire pool.ticket.v
        if (t & 0xfffff) < ((t >> 20) & 0xfffff)
            claim!(pool, id)
            idle = 0
        elseif idle < 1 << 18
            ccall(:jl_cpu_pause, Cvoid, ())
            # Let the garbage collector stop this thread whenever another thread needs it to
            GC.safepoint()
            idle += 1
        else
            Libc.systemsleep(0.0001)
            GC.safepoint()
        end
    end
    return nothing
end

# Start the persistent worker threads on every other Julia thread
function start_pool(n::Int)
    spawn = get(ENV, "COUNTDOWN_POOL", "spin") == "spawn"
    pool = Pool(n, spawn, Padded(0), Padded(0), 0, (Job(), Job()), Threads.SpinLock(), nothing, false)
    if !spawn
        mine = Threads.threadid()
        tids = [tid for tid in 1:Threads.maxthreadid() if tid != mine][1:n-1]
        for (k, tid) in enumerate(tids)
            task = Task(() -> work(pool, k + 1))
            task.sticky = true
            ccall(:jl_set_task_tid, Cint, (Any, Cint), task, tid - 1)
            schedule(task)
        end
        # Stop the workers before the runtime waits for every thread to reach a safepoint at exit
        atexit(() -> @atomic pool.stop = true)
    end
    return pool
end

# Hand a batch of items to every thread and return once all of them are done
function run_job!(pool::Union{Pool,Nothing}, s::State, kind::Int, masks::Vector{Int}, lefts::Vector{Int})
    count = max(length(masks), length(lefts))
    if pool === nothing
        job = Job(kind, s, masks, lefts)
        for i in 1:count
            run_item!(job, i, 1)
        end
        return nothing
    end
    pool.gen += 1
    job = pool.jobs[pool.gen & 1 + 1]
    job.kind, job.state, job.masks, job.lefts = kind, s, masks, lefts
    if pool.spawn
        # Hand each other thread a task that claims items alongside this one
        next = Threads.Atomic{Int}(0)
        go(id) = while (i = Threads.atomic_add!(next, 1) + 1) <= count
            run_item!(job, i, id)
        end
        tasks = [Threads.@spawn go(id) for id in 2:pool.threads]
        go(1)
        foreach(wait, tasks)
    else
        @atomic :release pool.done.v = zero(UInt64)
        @atomic :release pool.ticket.v = (UInt64(pool.gen) << 40) | (UInt64(count) << 20)
        claim!(pool, 1)
        while (@atomic :acquire pool.done.v) < count
            ccall(:jl_cpu_pause, Cvoid, ())
            # Let a worker that allocates while raising an error stop the world instead of waiting forever
            GC.safepoint()
        end
    end
    # Drop the reference so the pool keeps no round data between jobs
    job.state = nothing
    if pool.error !== nothing
        e, pool.error = pool.error, nothing
        throw(e)
    end
    return nothing
end

# Give every thread its own buffers the first time this solve shares work
function share!(s::State, count::Int)
    while length(s.scratch) < count
        push!(s.scratch, Scratch())
    end
    return nothing
end

# Make room in every thread's buffers for the values and reciprocals of the largest subset built so far
function reserve_rights!(s::State)
    biggest = maximum(view(s.len, 1:s.full))
    for sc in s.scratch
        if biggest > length(sc.rv)
            sc.rv = Vector{UInt32}(undef, 2 * biggest)
            sc.ri = Vector{Float64}(undef, 2 * biggest)
        end
    end
    return nothing
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
    left, a, b, op = find_way(s.scratch[1], s, mask, v)
    right = mask ⊻ left
    larger_mask, larger, smaller_mask, smaller = a >= b ? (left, a, right, b) : (right, b, left, a)
    bracket && push!(out, UInt8('('))
    render!(out, s, larger_mask, larger, true)
    push!(out, UInt8(' '), OP_CHARS[op], UInt8(' '))
    render!(out, s, smaller_mask, smaller, true)
    bracket && push!(out, UInt8(')'))
    return out
end

# Return the subset of this size that first makes the target or zero for none
function search(pool::Union{Pool,Nothing}, s::State, masks::Vector{Int}, size::Int)
    if pool === nothing || size < SEARCH_SIZE
        for mask in masks
            find_way(s.scratch[1], s, mask, s.target)[4] != 0 && return mask
        end
        return 0
    end
    # List every split of every subset in building order so the earliest item that hits is the first way
    items, lefts = Int[], Int[]
    for mask in masks
        left = (mask - 1) & mask
        while left != 0
            if left < mask ⊻ left
                push!(items, mask)
                push!(lefts, left)
            end
            left = (left - 1) & mask
        end
    end
    @atomic s.found = typemax(UInt64)
    share!(s, pool.threads)
    run_job!(pool, s, SEARCH, items, lefts)
    found = @atomic s.found
    return found == typemax(UInt64) ? 0 : items[Int(found)]
end

# Build every subset of this size sharing them across threads when there is enough work
function build_level!(pool::Union{Pool,Nothing}, s::State, masks::Vector{Int})
    # Reserve each subset its own region since no pair makes more than four values and none exceeds the bound
    total = 0
    for mask in masks
        room = 0
        left = (mask - 1) & mask
        while left != 0
            right = mask ⊻ left
            left < right && (room += s.len[left] * s.len[right])
            left = (left - 1) & mask
        end
        total += room
        s.off[mask] = s.top
        s.top += min(4 * room, Int(s.most[mask]))
    end
    length(s.vals) < s.top && resize!(s.vals, max(2 * length(s.vals), s.top))
    s.level_most = maximum(m -> s.most[m], masks)
    if pool === nothing || total < BUILD_MIN || length(masks) == 1
        reserve_rights!(s)
        for mask in masks
            build!(s.scratch[1], s, mask)
        end
    else
        # Hand out the busiest subsets first so the last to finish is a short one
        order = sort(masks; by = m -> -s.most[m])
        share!(s, pool.threads)
        reserve_rights!(s)
        run_job!(pool, s, BUILD, order, Int[])
    end
    return nothing
end

# Return the simplest expression that hits the target or gets closest to it, with its value
function solve(target::Integer, pool::AbstractVector{<:Integer})
    n = length(pool)
    1 <= n <= 6 || throw(ArgumentError("pool must hold one to six numbers"))
    # Keep every value below 2^32 so 32-bit arithmetic never wraps
    prod(UInt64(p) + 1 for p in pool) < UInt64(1) << 32 || throw(ArgumentError("pool numbers too large"))
    count = threads()
    workers = POOL[]
    if workers === nothing && count > 1
        workers = POOL[] = start_pool(count)
    end
    if workers === nothing
        return solve_with(nothing, target, pool, 1)
    end
    # Let one solve at a time use the pool so concurrent callers take turns
    lock(workers.lock)
    try
        return solve_with(workers, target, pool, workers.threads)
    finally
        unlock(workers.lock)
    end
end

function solve_with(workers::Union{Pool,Nothing}, target::Integer, pool::AbstractVector{<:Integer}, count::Int)
    n = length(pool)
    full = (1 << n) - 1
    t = UInt32(target)
    s = State(t, n, full, Vector{UInt32}(undef, 256), n, zeros(Int, 64), zeros(Int, 64), zeros(UInt64, 64), 0,
              [Scratch()], typemax(UInt64), typemax(UInt64))
    try
        return solve_state(workers, s, target, pool)
    finally
        # Free every thread's bitset since the garbage collector does not own them
        for sc in s.scratch
            sc.seen == C_NULL || Libc.free(sc.seen)
            sc.seen = Ptr{UInt64}(0)
        end
    end
end

function solve_state(workers::Union{Pool,Nothing}, s::State, target::Integer, pool::AbstractVector{<:Integer})
    n, full, t = s.n, s.full, s.target

    # Work out each subset's largest value since subtracting and dividing never exceed the larger operand
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
    end

    # Store each pool number as a one-number subset
    for i in 1:n
        s.vals[i] = UInt32(pool[i])
        s.off[1 << (i - 1)] = i - 1
        s.len[1 << (i - 1)] = 1
    end
    i = findfirst(==(target), pool)
    hit = i === nothing ? 0 : 1 << (i - 1)

    by_size = MASKS[n]

    # Work through subsets smallest first stopping at the first size that hits the target
    size = 2
    while hit == 0 && size <= n
        hit = search(workers, s, by_size[size], size)
        # Skip building the whole pool's values since no larger subset is made from them
        (hit != 0 || size == n) && break
        build_level!(workers, s, by_size[size])
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
        lefts = Int[]
        pairs = 0
        left = (full - 1) & full
        while left != 0
            if left < full ⊻ left
                push!(lefts, left)
                pairs += s.len[left] * s.len[full ⊻ left]
            end
            left = (left - 1) & full
        end
        sharing = workers !== nothing && pairs >= WHOLE_MIN
        sharing && share!(s, workers.threads)
        reserve_rights!(s)
        run_job!(sharing ? workers : nothing, s, WHOLE, Int[], lefts)
        key = @atomic s.nearest
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
