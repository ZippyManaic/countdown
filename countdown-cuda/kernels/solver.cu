// Solve one Countdown round per thread block with every subset's values held in a shared-memory hash table

typedef unsigned int u32;
typedef unsigned long long u64;
typedef unsigned short u16;
typedef unsigned char u8;

#define THREADS 512
#define WARPS (THREADS / 32)
#define MAX_POOL 6
// Hold every value of subsets up to two smaller than the pool in a shared-memory table
#define SMALL_SLOTS 5120u
// List only the values of subsets up to three smaller than the pool since searches never scan larger ones
#define SMALL_LIST 1088
// Hold the values of subsets one smaller than the pool in global memory since few rounds need them
#define BIG_SLOTS 16384u
#define BIG_LIST 20480
// Pack shared-memory keys as a subset over 24 bits of value since no dealt pool's subsets two smaller reach 2^24
#define VALUE_BITS 24
#define VALUE_LIMIT (1u << VALUE_BITS)
#define VALUE_MASK (VALUE_LIMIT - 1)
// Give each operand of a way 27 bits since cats pools' subsets one smaller than the pool reach 93,750,000
#define WAY_BITS 27
#define WAY_MASK ((1u << WAY_BITS) - 1)
#define NONE 0xFFFFFFFFFFFFFFFFull
#define TEXT 64
// Allow every split of every subset of six numbers
#define MAX_SPLITS 320
#define MAX_JOBS 256
#define MAX_QUERIES 40
#define MAX_NODES 16
#define LEAF 4u
#define PENDING 5u

enum { OP_ADD, OP_SUB, OP_MUL, OP_DIV };
enum { ERROR_LIST = 1, ERROR_TABLE = 2, ERROR_QUEUE = 4 };

// Hold a way of making the target that waits on whether a subset with unstored values can make its partner
struct Query {
    u32 mask, k, a, b, op, other, value;
};

struct Node {
    u32 mask, value, op, larger, smaller, length, start;
};

struct State {
    u32 table[SMALL_SLOTS];
    u32 list[SMALL_LIST];
    u32 off[64], len[64], fill[64];
    // List every split in building order grouped by subset size then subset
    u8 split_mask[MAX_SPLITS], split_left[MAX_SPLITS], split_k[MAX_SPLITS];
    u16 level_start[MAX_POOL + 2], mask_start[64];
    u8 mask_splits[64];
    // Describe each search or pairing job with its share of the flattened work
    u32 job_prefix[MAX_JOBS + 1], job_value[MAX_JOBS];
    u16 job_split[MAX_JOBS];
    u8 job_slot[MAX_JOBS];
    u32 jobs;
    u32 warp_sums[WARPS];
    u64 results[MAX_QUERIES + 1];
    Query queries[MAX_QUERIES];
    u32 queued;
    Node nodes[MAX_NODES];
    u32 node_count;
    u32 target, n, full, big_size, table_only, global_from, small_used, global_used, big_from, error, round;
    // Mark which subset sizes can be looked up and which can be scanned
    u32 stored[MAX_POOL + 1], listed[MAX_POOL + 1];
    u64 best, nearest;
    char text[TEXT];
};

// Pack global-memory keys for subsets one smaller than the pool in 32 bits when every value is below 2^24
struct Narrow {
    typedef u32 Key;
    static const u32 SHIFT = VALUE_BITS;
    static const u32 LIMIT = VALUE_LIMIT;
    static const u32 MASK = VALUE_MASK;
};

// Pack them in 64 bits with the subset above the value for pools whose largest values need up to 27 bits
struct Wide {
    typedef u64 Key;
    static const u32 SHIFT = 32;
    static const u32 LIMIT = 1u << WAY_BITS;
    static const u32 MASK = WAY_MASK;
};

template <class P> struct Scratch {
    typename P::Key *table, *list;
};

// Spread keys over any number of slots by taking the high half of a scaled multiplicative hash
__device__ __forceinline__ u32 slot_of(u32 key, u32 slots)
{
    return __umulhi(key * 2654435761u, slots);
}

// Fold the subset into the spare high bits of the value before hashing a wide key
__device__ __forceinline__ u32 slot_of(u64 key, u32 slots)
{
    return slot_of((u32)key ^ (u32)(key >> 32) << WAY_BITS, slots);
}

// Add a key to a hash table and return whether it was new, flagging an error if the table is full
template <class K> __device__ bool insert(K *table, u32 slots, K key, u32 *error)
{
    u32 s = slot_of(key, slots);
    for (u32 probe = 0; probe < slots; probe++) {
        K old = atomicCAS(&table[s], (K)0, key);
        if (old == 0)
            return true;
        if (old == key)
            return false;
        s = s + 1 == slots ? 0 : s + 1;
    }
    atomicOr(error, (u32)ERROR_TABLE);
    return false;
}

template <class K> __device__ bool contains(const K *table, u32 slots, K key)
{
    u32 s = slot_of(key, slots);
    for (;;) {
        K k = table[s];
        if (k == key)
            return true;
        if (k == 0)
            return false;
        s = s + 1 == slots ? 0 : s + 1;
    }
}

__device__ __forceinline__ u32 size_of(u32 mask)
{
    return __popc(mask);
}

__device__ __forceinline__ bool is_big(const State *s, u32 mask)
{
    return size_of(mask) == s->big_size;
}

// Return whether a stored subset can make a value
template <class P> __device__ __forceinline__ bool has(const State *s, Scratch<P> g, u32 mask, u32 value)
{
    if (is_big(s, mask))
        return value < P::LIMIT && value != 0 &&
               contains(g.table, BIG_SLOTS, (typename P::Key)mask << P::SHIFT | value);
    if (value >= VALUE_LIMIT || value == 0)
        return false;
    return contains(s->table, SMALL_SLOTS, mask << VALUE_BITS | value);
}

// Return the value at a position in a subset's list
template <class P> __device__ __forceinline__ u32 value_at(const State *s, Scratch<P> g, u32 mask, u32 i)
{
    u32 at = s->off[mask] + i;
    return size_of(mask) >= s->global_from ? (u32)g.list[at] & P::MASK : s->list[at] & VALUE_MASK;
}

// Fill m and op with every number that combines with a to make t in operator order and return how many
template <class P> __device__ __forceinline__ int partners(u32 a, u32 t, u32 *m, u32 *op)
{
    int count = 0;
    if (t > a)
        m[count] = t - a, op[count++] = OP_ADD;
    if (a > t)
        m[count] = a - t, op[count++] = OP_SUB;
    m[count] = a + t, op[count++] = OP_SUB;
    // Divide only when the quotient could be at least two since neither operand may be one
    if (a != 1 && 2 * a <= t && t % a == 0)
        m[count] = t / a, op[count++] = OP_MUL;
    if (a >= 2 * t && a % t == 0)
        m[count] = a / t, op[count++] = OP_DIV;
    if (a != 1 && (u64)a * t < P::LIMIT)
        m[count] = a * t, op[count++] = OP_DIV;
    return count;
}

// Order ways of making a value by split, left value, right value and operator so the minimum is building's first
__device__ __forceinline__ u64 way(u32 k, u32 a, u32 b, u32 op)
{
    return (u64)k << (2 * WAY_BITS + 2) | (u64)a << (WAY_BITS + 2) | (u64)b << 2 | op;
}

// Return the exclusive prefix sum of x across the block and leave the total in total
__device__ u32 block_scan(State *s, u32 x, u32 *total)
{
    u32 lane = threadIdx.x & 31, warp = threadIdx.x >> 5, v = x;
    for (u32 d = 1; d < 32; d <<= 1) {
        u32 y = __shfl_up_sync(0xFFFFFFFFu, v, d);
        if (lane >= d)
            v += y;
    }
    if (lane == 31)
        s->warp_sums[warp] = v;
    __syncthreads();
    if (warp == 0) {
        u32 w = lane < WARPS ? s->warp_sums[lane] : 0;
        for (u32 d = 1; d < 32; d <<= 1) {
            u32 y = __shfl_up_sync(0xFFFFFFFFu, w, d);
            if (lane >= d)
                w += y;
        }
        if (lane < WARPS)
            s->warp_sums[lane] = w;
    }
    __syncthreads();
    u32 before = (warp ? s->warp_sums[warp - 1] : 0) + v - x;
    *total = s->warp_sums[WARPS - 1];
    __syncthreads();
    return before;
}

// Return the job holding a flattened item by searching the jobs' running totals
__device__ __forceinline__ u32 job_of(const State *s, u32 item)
{
    u32 lo = 0, hi = s->jobs;
    while (hi - lo > 1) {
        u32 mid = (lo + hi) / 2;
        if (s->job_prefix[mid] <= item)
            lo = mid;
        else
            hi = mid;
    }
    return lo;
}

// Describe how a search job scans one side of its split for partners on the other
struct Scan {
    u32 mask, left, right, k, scan, other, count;
    bool scan_left, other_stored;
};

__device__ __forceinline__ Scan scan_of(const State *s, u32 split)
{
    Scan c;
    c.mask = s->split_mask[split];
    c.left = s->split_left[split];
    c.right = c.mask ^ c.left;
    c.k = s->split_k[split];
    bool left_listed = s->listed[size_of(c.left)], right_listed = s->listed[size_of(c.right)];
    u32 nl = s->len[c.left], nr = s->len[c.right];
    // Scan the shorter listed side and look for each value's partners on the other like the C version
    c.scan_left = left_listed && (!right_listed || nl <= nr);
    c.scan = c.scan_left ? c.left : c.right;
    c.other = c.scan_left ? c.right : c.left;
    c.count = c.scan_left ? nl : nr;
    c.other_stored = s->stored[size_of(c.other)];
    return c;
}

// Search every job's split for ways to make its value folding each into its result slot
template <class P> __device__ void run_search(State *s, Scratch<P> g, bool level_order, bool queue)
{
    u32 t = threadIdx.x, count = 0;
    if (t < s->jobs)
        count = scan_of(s, s->job_split[t]).count;
    u32 total, before = block_scan(s, count, &total);
    if (t < s->jobs)
        s->job_prefix[t] = before;
    __syncthreads();
    for (u32 item = t; item < total; item += THREADS) {
        u32 job = job_of(s, item);
        Scan c = scan_of(s, s->job_split[job]);
        u32 v = value_at(s, g, c.scan, item - s->job_prefix[job]), value = s->job_value[job];
        // Number splits across the level when ways from different subsets compete so the subset orders first
        u32 k = level_order ? s->job_split[job] - s->level_start[size_of(c.mask)] : c.k;
        u32 m[6], op[6];
        int pc = partners<P>(v, value, m, op);
        for (int i = 0; i < pc; i++) {
            u32 a = c.scan_left ? v : m[i], b = c.scan_left ? m[i] : v;
            if (c.other_stored) {
                if (has(s, g, c.other, m[i]))
                    atomicMin(&s->results[s->job_slot[job]], way(k, a, b, op[i]));
            } else if (queue && m[i] < P::LIMIT) {
                u32 q = atomicAdd(&s->queued, 1u);
                if (q < MAX_QUERIES)
                    s->queries[q] = Query{c.mask, k, a, b, op[i], c.other, m[i]};
                else
                    atomicOr(&s->error, (u32)ERROR_QUEUE);
            }
        }
    }
    __syncthreads();
}

// Return the first way building makes the target from any subset of this size numbering splits across the level
template <class P> __device__ u64 find_exact(State *s, Scratch<P> g, u32 size)
{
    u32 t = threadIdx.x, first = s->level_start[size], splits = s->level_start[size + 1] - first;
    if (t < splits) {
        s->job_split[t] = first + t;
        s->job_value[t] = s->target;
        s->job_slot[t] = 0;
    }
    if (t == 0) {
        s->jobs = splits;
        s->results[0] = NONE;
        s->queued = 0;
    }
    __syncthreads();
    run_search(s, g, true, true);
    // Check queued partners against subsets with unstored values by searching those subsets' own splits
    u32 queued = min(s->queued, (u32)MAX_QUERIES);
    for (u32 done = 0; done < queued;) {
        u32 per = s->mask_splits[s->queries[done].other], batch = min(queued - done, (u32)(MAX_JOBS / per));
        if (t < batch * per) {
            Query q = s->queries[done + t / per];
            s->job_split[t] = s->mask_start[q.other] + t % per;
            s->job_value[t] = q.value;
            s->job_slot[t] = 1 + t / per;
        }
        if (t < batch)
            s->results[1 + t] = NONE;
        if (t == 0)
            s->jobs = batch * per;
        __syncthreads();
        run_search(s, g, false, false);
        if (t < batch && s->results[1 + t] != NONE) {
            Query q = s->queries[done + t];
            atomicMin(&s->results[0], way(q.k, q.a, q.b, q.op));
        }
        done += batch;
        __syncthreads();
    }
    return s->results[0];
}

// Return the first way building makes a value from a subset as split, values and operator
template <class P> __device__ u64 first_way(State *s, Scratch<P> g, u32 mask, u32 value)
{
    u32 t = threadIdx.x;
    if (t < s->mask_splits[mask]) {
        s->job_split[t] = s->mask_start[mask] + t;
        s->job_value[t] = value;
        s->job_slot[t] = 0;
    }
    if (t == 0) {
        s->jobs = s->mask_splits[mask];
        s->results[0] = NONE;
    }
    __syncthreads();
    run_search(s, g, false, false);
    return s->results[0];
}

// Make every split of every subset of this size a job whose items are its pairs of values and return their count
__device__ u32 pair_jobs(State *s, u32 size)
{
    u32 t = threadIdx.x, first = s->level_start[size], splits = s->level_start[size + 1] - first, count = 0;
    if (t < splits) {
        u32 split = first + t, left = s->split_left[split], right = s->split_mask[split] ^ left;
        s->job_split[t] = split;
        count = s->len[left] * s->len[right];
    }
    if (t == 0)
        s->jobs = splits;
    u32 total, before = block_scan(s, count, &total);
    if (t < splits)
        s->job_prefix[t] = before;
    __syncthreads();
    return total;
}

// Return the pair of values behind a flattened item with its split
template <class P>
__device__ __forceinline__ void pair_of(const State *s, Scratch<P> g, u32 item, u32 *mask, u32 *k, u32 *a, u32 *b)
{
    u32 job = job_of(s, item), split = s->job_split[job], p = item - s->job_prefix[job];
    u32 left = s->split_left[split], right = s->split_mask[split] ^ left, nr = s->len[right], i = p / nr;
    *mask = s->split_mask[split];
    *k = s->split_k[split];
    *a = value_at(s, g, left, i);
    *b = value_at(s, g, right, p - i * nr);
}

// Count and list in global memory the values of every subset of this size held in a table packed with this shift
template <class P, class K> __device__ void list_values(State *s, Scratch<P> g, const K *table, u32 slots, u32 shift, u32 size)
{
    u32 t = threadIdx.x;
    for (u32 i = t; i < slots; i += THREADS) {
        K key = table[i];
        if (key && size_of((u32)(key >> shift)) == size)
            atomicAdd(&s->fill[key >> shift], 1u);
    }
    __syncthreads();
    if (t == 0) {
        u32 used = s->global_used;
        for (u32 mask = 1; mask <= s->full; mask++) {
            if (size_of(mask) == size) {
                s->off[mask] = used;
                s->len[mask] = s->fill[mask];
                used += s->fill[mask];
                s->fill[mask] = 0;
            }
        }
        if (used > BIG_LIST)
            atomicOr(&s->error, (u32)ERROR_LIST);
        s->global_used = used;
        s->listed[size] = 1;
    }
    __syncthreads();
    for (u32 i = t; i < slots; i += THREADS) {
        K key = table[i];
        u32 mask = (u32)(key >> shift);
        if (key && size_of(mask) == size) {
            u32 at = s->off[mask] + atomicAdd(&s->fill[mask], 1u);
            // Keep the subset with each value so the closest search can scan the list directly
            if (at < BIG_LIST)
                g.list[at] = (typename P::Key)mask << P::SHIFT | ((u32)key & (u32)(((K)1 << shift) - 1));
        }
    }
    __syncthreads();
    if (t < 64)
        s->fill[t] = 0;
    __syncthreads();
}

// Store every value each subset of this size can make
template <class P> __device__ void build(State *s, Scratch<P> g, u32 size)
{
    u32 t = threadIdx.x;
    bool big = size == s->big_size;
    // List small subsets as values are found and leave the rest to a table scan only if a round needs them
    bool listed = !big && size != s->table_only;
    if (big)
        for (u32 i = t; i < BIG_SLOTS; i += THREADS)
            g.table[i] = 0;
    u32 total = pair_jobs(s, size);
    if (listed) {
        // Reserve each subset four entries per pair since no pair makes more than four values
        if (t < s->jobs && s->split_k[s->job_split[t]] == 0) {
            u32 mask = s->split_mask[s->job_split[t]];
            s->off[mask] = s->small_used + 4 * s->job_prefix[t];
            s->len[mask] = 0;
        }
        if (t == 0 && s->small_used + 4 * total > SMALL_LIST)
            atomicOr(&s->error, (u32)ERROR_LIST);
        __syncthreads();
    }
    for (u32 item = t; item < total; item += THREADS) {
        u32 mask, k, a, b;
        pair_of(s, g, item, &mask, &k, &a, &b);
        u32 x = max(a, b), y = min(a, b);
        u32 made[4], count = 0;
        made[count++] = x + y;
        // Skip a zero result since every intermediate value must be a positive integer
        if (x != y)
            made[count++] = x - y;
        // Skip multiplying and dividing by one as they never produce a new value
        if (y != 1) {
            made[count++] = x * y;
            if (x % y == 0)
                made[count++] = x / y;
        }
        for (u32 i = 0; i < count; i++) {
            bool fresh = big ? insert(g.table, BIG_SLOTS, (typename P::Key)mask << P::SHIFT | made[i], &s->error)
                             : insert(s->table, SMALL_SLOTS, mask << VALUE_BITS | made[i], &s->error);
            if (fresh && listed) {
                u32 at = s->off[mask] + atomicAdd(&s->len[mask], 1u);
                if (at < SMALL_LIST)
                    s->list[at] = made[i];
            }
        }
    }
    __syncthreads();
    if (t == 0) {
        s->stored[size] = 1;
        s->listed[size] = listed;
        if (listed)
            s->small_used += 4 * total;
    }
    __syncthreads();
    if (big)
        list_values(s, g, g.table, BIG_SLOTS, P::SHIFT, size);
}

// Fold every whole-pool value into out as distance then value, or with nearest given the first way to make it
template <class P> __device__ void whole(State *s, Scratch<P> g, u64 nearest, u64 *out)
{
    if (threadIdx.x == 0)
        *out = NONE;
    u32 total = pair_jobs(s, s->n);
    for (u32 item = threadIdx.x; item < total; item += THREADS) {
        u32 mask, k, a, b;
        pair_of(s, g, item, &mask, &k, &a, &b);
        u64 x = max(a, b), y = min(a, b);
        u64 results[4] = {x + y, x != y ? x - y : 0, y != 1 ? x * y : 0, y != 1 && x % y == 0 ? x / y : 0};
        for (u32 op = 0; op < 4; op++) {
            u64 v = results[op];
            // Skip illegal results and products too large to be nearest since a sum is always closer
            if (v == 0 || v >= 1ull << 32)
                continue;
            u64 near = (v > s->target ? v - s->target : s->target - v) << 32 | v;
            if (!nearest)
                atomicMin(out, near);
            else if (near == nearest)
                atomicMin(out, way(k, a, b, op));
        }
    }
    __syncthreads();
}

// Fill a node's operator and children from the first way of making it with its split counted from first
__device__ void expand_node(State *s, u32 index, u64 key, u32 first)
{
    Node *node = &s->nodes[index];
    u32 k = (u32)(key >> (2 * WAY_BITS + 2)), a = (u32)(key >> (WAY_BITS + 2)) & WAY_MASK, b = (u32)(key >> 2) & WAY_MASK;
    u32 left = s->split_left[first + k], right = node->mask ^ left;
    bool a_larger = a >= b;
    u32 big = a_larger ? left : right, small = a_larger ? right : left;
    node->op = (u32)key & 3;
    node->larger = s->node_count;
    node->smaller = s->node_count + 1;
    s->nodes[s->node_count++] = Node{big, a_larger ? a : b, size_of(big) > 1 ? PENDING : LEAF, 0, 0, 0, 0};
    s->nodes[s->node_count++] = Node{small, a_larger ? b : a, size_of(small) > 1 ? PENDING : LEAF, 0, 0, 0, 0};
}

// Work out every pending node's way of being made a level at a time until every leaf is a pool number
template <class P> __device__ void unfold(State *s, Scratch<P> g)
{
    for (u32 from = 0; from < s->node_count;) {
        u32 end = s->node_count;
        // Search every pending node of this level together with a result slot each
        if (threadIdx.x == 0) {
            u32 jobs = 0;
            for (u32 i = from; i < end; i++) {
                Node node = s->nodes[i];
                if (node.op != PENDING)
                    continue;
                s->results[i - from] = NONE;
                for (u32 k = 0; k < s->mask_splits[node.mask]; k++, jobs++) {
                    s->job_split[jobs] = s->mask_start[node.mask] + k;
                    s->job_value[jobs] = node.value;
                    s->job_slot[jobs] = i - from;
                }
            }
            s->jobs = jobs;
        }
        __syncthreads();
        if (s->jobs) {
            run_search(s, g, false, false);
            if (threadIdx.x == 0)
                for (u32 i = from; i < end; i++)
                    if (s->nodes[i].op == PENDING)
                        expand_node(s, i, s->results[i - from], s->mask_start[s->nodes[i].mask]);
            __syncthreads();
        }
        from = end;
    }
}

__device__ __forceinline__ u32 digits_of(u32 n)
{
    u32 d = 1;
    while (n >= 10)
        n /= 10, d++;
    return d;
}

// Write the expression with each node placing its own characters once lengths and starts are known
__device__ void render(State *s)
{
    u32 t = threadIdx.x, count = s->node_count;
    if (t == 0) {
        // Size nodes from the leaves up since children always follow their parent
        for (u32 i = count; i-- > 0;) {
            Node *node = &s->nodes[i];
            node->length = node->op == LEAF ? digits_of(node->value)
                                            : s->nodes[node->larger].length + s->nodes[node->smaller].length + 3 +
                                                  (i ? 2 : 0);
        }
        s->nodes[0].start = 0;
        for (u32 i = 0; i < count; i++) {
            Node *node = &s->nodes[i];
            if (node->op != LEAF) {
                // Leave the root unbracketed
                s->nodes[node->larger].start = node->start + (i ? 1 : 0);
                s->nodes[node->smaller].start = s->nodes[node->larger].start + s->nodes[node->larger].length + 3;
            }
        }
        s->text[s->nodes[0].length] = '\0';
    }
    __syncthreads();
    if (t < count) {
        Node node = s->nodes[t];
        char *out = s->text + node.start;
        if (node.op == LEAF) {
            u32 v = node.value;
            for (u32 d = node.length; d-- > 0; v /= 10)
                out[d] = (char)('0' + v % 10);
        } else {
            if (t) {
                out[0] = '(';
                out[node.length - 1] = ')';
            }
            char *gap = s->text + s->nodes[node.larger].start + s->nodes[node.larger].length;
            gap[0] = ' ';
            gap[1] = "+-*/"[node.op];
            gap[2] = ' ';
        }
    }
    __syncthreads();
}

// Fill the split tables which depend only on the pool size
__device__ void list_splits(State *s, u32 n)
{
    u32 count = 0, full = (1u << n) - 1;
    for (u32 size = 1; size <= n; size++) {
        s->level_start[size] = count;
        for (u32 mask = 1; mask <= full; mask++) {
            if (size_of(mask) != size)
                continue;
            u32 k = 0;
            s->mask_start[mask] = count;
            for (u32 left = (mask - 1) & mask; left; left = (left - 1) & mask) {
                // Visit each split once rather than once per ordering
                if (left < (mask ^ left)) {
                    s->split_mask[count] = mask;
                    s->split_left[count] = left;
                    s->split_k[count] = k++;
                    count++;
                }
            }
            s->mask_splits[mask] = k;
        }
    }
    s->level_start[n + 1] = count;
}

template <class P>
__device__ void solve_rounds(const u32 *rounds, u32 count, u32 n, u32 *out_value, char *out_text, u32 *next,
                             typename P::Key *big_tables, typename P::Key *big_lists, u32 *errors)
{
    extern __shared__ unsigned char shared[];
    State *s = (State *)shared;
    Scratch<P> g = {big_tables + (size_t)blockIdx.x * BIG_SLOTS, big_lists + (size_t)blockIdx.x * BIG_LIST};
    u32 t = threadIdx.x;
    if (t == 0)
        list_splits(s, n);
    for (;;) {
        // Take rounds from a shared counter so blocks that finish early pick up more work
        if (t == 0)
            s->round = atomicAdd(next, 1u);
        __syncthreads();
        u32 round = s->round;
        if (round >= count)
            return;
        const u32 *r = rounds + (size_t)round * (n + 1);
        for (u32 i = t; i < SMALL_SLOTS; i += THREADS)
            s->table[i] = 0;
        if (t < 64)
            s->off[t] = s->len[t] = s->fill[t] = 0;
        if (t <= MAX_POOL)
            s->stored[t] = s->listed[t] = t == 1;
        if (t == 0) {
            s->target = r[0];
            s->n = n;
            s->full = (1u << n) - 1;
            // Leave subsets one smaller than the pool unstored until a round needs them
            s->big_size = n >= 3 ? n - 1 : 0;
            // Keep subsets two smaller than the pool as a table only when every split they need has a listed side
            s->table_only = n >= 5 ? n - 2 : 0;
            s->global_from = n >= 5 ? n - 2 : max(n - 1, 2u);
            s->small_used = n;
            s->global_used = 0;
            s->error = 0;
            s->node_count = 0;
        }
        __syncthreads();
        // Store each pool number as a one-number subset
        if (t < n) {
            s->list[t] = r[1 + t];
            s->off[1u << t] = t;
            s->len[1u << t] = 1;
            insert(s->table, SMALL_SLOTS, (1u << t) << VALUE_BITS | r[1 + t], &s->error);
        }
        if (t == 0) {
            for (u32 i = 0; i < n; i++) {
                if (r[1 + i] == s->target) {
                    s->nodes[s->node_count++] = Node{1u << i, s->target, LEAF, 0, 0, 0, 0};
                    break;
                }
            }
        }
        __syncthreads();

        // Work through subsets smallest first stopping at the first size that hits the target
        for (u32 size = 2; size <= n && s->node_count == 0; size++) {
            u64 key = find_exact(s, g, size);
            if (key != NONE) {
                if (t == 0) {
                    u32 first = s->level_start[size], mask = s->split_mask[first + (u32)(key >> (2 * WAY_BITS + 2))];
                    s->nodes[s->node_count++] = Node{mask, s->target, PENDING, 0, 0, 0, 0};
                    expand_node(s, 0, key, first);
                }
                __syncthreads();
                break;
            }
            if (size + 2 <= n)
                build(s, g, size);
        }

        if (s->node_count == 0) {
            if (s->table_only)
                list_values(s, g, s->table, SMALL_SLOTS, VALUE_BITS, s->table_only);
            if (t == 0)
                s->big_from = s->global_used;
            __syncthreads();
            if (s->big_size >= 2)
                build(s, g, s->big_size);
            // Rank by distance from the target then by how many numbers are used then by subset and value
            if (t == 0)
                s->best = NONE;
            __syncthreads();
            // Scan the shared table for smaller subsets and the global list for the largest
            u32 big_count = s->global_used - s->big_from;
            for (u32 i = t; i < SMALL_SLOTS + big_count; i += THREADS) {
                u32 mask, v;
                if (i < SMALL_SLOTS) {
                    u32 key = s->table[i];
                    if (key == 0)
                        continue;
                    mask = key >> VALUE_BITS, v = key & VALUE_MASK;
                } else {
                    typename P::Key key = g.list[s->big_from + i - SMALL_SLOTS];
                    mask = (u32)(key >> P::SHIFT), v = (u32)key & P::MASK;
                }
                u32 d = v > s->target ? v - s->target : s->target - v;
                atomicMin(&s->best, (u64)d << 36 | (u64)size_of(mask) << 33 | (u64)mask << WAY_BITS | v);
            }
            __syncthreads();
            // Check the whole pool's values as they are made since no larger subset is built from them
            whole(s, g, 0, &s->nearest);
            // Fall back to the whole pool only when it gets strictly closer as it uses the most numbers
            if ((s->nearest >> 32) < (s->best >> 36)) {
                whole(s, g, s->nearest, &s->results[0]);
                if (t == 0) {
                    s->nodes[s->node_count++] = Node{s->full, (u32)s->nearest, PENDING, 0, 0, 0, 0};
                    expand_node(s, 0, s->results[0], s->level_start[n]);
                }
            } else if (t == 0) {
                u32 mask = (u32)(s->best >> WAY_BITS) & 63, v = (u32)s->best & WAY_MASK;
                s->nodes[s->node_count++] = Node{mask, v, size_of(mask) > 1 ? PENDING : LEAF, 0, 0, 0, 0};
            }
            __syncthreads();
        }

        unfold(s, g);
        // Render without outer brackets which matches stripping them from the bracketed form
        render(s);
        if (t == 0) {
            out_value[round] = s->nodes[0].value;
            if (s->error)
                atomicOr(errors, s->error);
        }
        __syncthreads();
        // Copy the text out a word per thread rather than a byte at a time
        if (t < TEXT / 4)
            ((u32 *)(out_text + (size_t)round * TEXT))[t] = ((const u32 *)s->text)[t];
        __syncthreads();
    }
}

extern "C" __global__ void __launch_bounds__(THREADS, 3) solve(const u32 *rounds, u32 count, u32 n, u32 *out_value,
                                                             char *out_text, u32 *next, u32 *big_tables,
                                                             u32 *big_lists, u32 *errors)
{
    solve_rounds<Narrow>(rounds, count, n, out_value, out_text, next, big_tables, big_lists, errors);
}

// Solve rounds whose subsets one smaller than the pool make values of 2^24 or more
extern "C" __global__ void __launch_bounds__(THREADS, 3) solve_wide(const u32 *rounds, u32 count, u32 n,
                                                                  u32 *out_value, char *out_text, u32 *next,
                                                                  u64 *big_tables, u64 *big_lists, u32 *errors)
{
    solve_rounds<Wide>(rounds, count, n, out_value, out_text, next, big_tables, big_lists, errors);
}

// Report the shared memory each block needs so the host can reserve it
extern "C" __global__ void state_size(u32 *out)
{
    *out = sizeof(State);
}
