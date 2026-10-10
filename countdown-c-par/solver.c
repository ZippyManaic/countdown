// Solve one Countdown round with several threads sharing each level's subsets while keeping the sequential answer
#define _GNU_SOURCE
#include "solver.h"

#include <immintrin.h>
#include <limits.h>
#include <linux/futex.h>
#include <pthread.h>
#include <sched.h>
#include <stdatomic.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/syscall.h>
#include <unistd.h>

// Sort subsets with fewer values than this by insertion rather than by rank in the bitset
#define RANK_MIN 16
// Allow at most this many threads including the caller
#define MAX_THREADS 64
// Share a level's building only when it combines at least this many pairs of values
#ifndef BUILD_MIN
#define BUILD_MIN 400
#endif
// Share a level's searching only when it scans at least this many values
#ifndef SEARCH_MIN
#define SEARCH_MIN 100
#endif
// Share levels only from this many numbers up since smaller levels never repay the dispatch
#ifndef FROM_SIZE
#define FROM_SIZE 4
#endif
// Spin this many pauses waiting for work before a worker sleeps
#ifndef SPIN_LIMIT
#define SPIN_LIMIT (1u << 17)
#endif

enum { OP_ADD = '+', OP_SUB = '-', OP_MUL = '*', OP_DIV = '/' };

// Record a reachable value with how it was made from the larger and smaller of two values in disjoint subsets
typedef struct {
    uint32_t value;
    // Leave the operator as zero for a pool number
    uint8_t op;
    uint8_t larger_mask;
    uint8_t smaller_mask;
    uint8_t pad;
    uint32_t larger;
    uint32_t smaller;
} entry;

_Static_assert(sizeof(entry) == 16, "entries must pack into two words for branchless stores");

// Hold one thread's private working memory for a solve on its own cache lines
typedef struct {
    _Alignas(64) uint64_t *seen;
    size_t seen_words;
    // Collect a subset's new values here before they are sorted into the arena
    entry *tmp;
    size_t tmp_cap;
    // Hold the count of values below each bitset word for ranking
    uint32_t *rank;
    // Hold the right half's values with their reciprocals for the split being built
    uint32_t *right_values;
    double *right_inv;
    size_t right_cap;
} scratch;

// Hold the whole pool's closest value from one split with the way it was first made
typedef struct {
    uint32_t distance;
    uint64_t head, operands;
} closest;

// Hold the working memory of one solve
typedef struct {
    uint32_t target;
    unsigned full;
    // Keep every subset's sorted values in one arena that threads reserve space in atomically
    entry *arena;
    size_t cap;
    _Atomic size_t top;
    uint32_t off[256], len[256];
    // Hold the largest value each subset can make which bounds the bitset words it touches
    uint32_t max[256];
    // Describe the level being worked on for the jobs the pool runs
    const uint8_t *masks;
    uint32_t largest, biggest;
    // Say whether the level's subsets are shared between threads so the arena must not move
    bool shared;
    // Hold each subset's way of making the target and the lowest subset index found so far
    entry hits[128];
    _Atomic unsigned found;
    // Hold the whole pool's splits in canonical order and each one's closest value
    unsigned splits[128];
    uint8_t split_order[128];
    closest near[128];
    // Point at one scratch per thread allocated with the solve
    scratch *scr;
} state;

static void *grow(void *p, size_t *cap, size_t need, size_t size)
{
    if (need <= *cap)
        return p;
    while (*cap < need)
        *cap = *cap ? *cap * 2 : 1024;
    p = realloc(p, *cap * size);
    if (!p) {
        perror("realloc");
        exit(2);
    }
    return p;
}

// Run a job over a number of items as fn(ctx, item, thread)
typedef void (*job_fn)(state *s, unsigned item, unsigned thread);

// Keep the worker threads and the job they share, each hot field on its own cache line
static struct {
    // Hold the job generation in the top half and the next unclaimed item in the bottom half
    _Alignas(64) _Atomic uint64_t ticket;
    _Alignas(64) _Atomic uint32_t done;
    _Alignas(64) _Atomic uint32_t epoch;
    _Atomic int sleepers;
    // Double-buffer the job so a worker reading a finished job never sees the next one half written
    struct {
        job_fn fn;
        state *s;
        _Atomic unsigned items;
    } slot[2];
    unsigned threads;
    uint32_t gen;
} pool;

static pthread_once_t pool_once = PTHREAD_ONCE_INIT;

// Claim and run the items of job generation g until none are left or a newer job starts
static void work(uint32_t g, unsigned thread)
{
    for (;;) {
        uint64_t t = atomic_load_explicit(&pool.ticket, memory_order_acquire);
        if ((uint32_t)(t >> 32) != g)
            return;
        if ((uint32_t)t >= atomic_load_explicit(&pool.slot[g & 1].items, memory_order_relaxed))
            return;
        if (!atomic_compare_exchange_weak_explicit(&pool.ticket, &t, t + 1, memory_order_acquire,
                                                   memory_order_relaxed))
            continue;
        // Read the job only after claiming an item which proves the job is still running
        pool.slot[g & 1].fn(pool.slot[g & 1].s, (uint32_t)t, thread);
        atomic_fetch_add_explicit(&pool.done, 1, memory_order_release);
    }
}

static void *worker(void *arg)
{
    unsigned thread = (unsigned)(uintptr_t)arg;
    uint32_t last = 0;
    unsigned spins = 0;
    for (;;) {
        uint32_t g = (uint32_t)(atomic_load_explicit(&pool.ticket, memory_order_acquire) >> 32);
        if (g != last) {
            work(g, thread);
            last = g;
            spins = 0;
            continue;
        }
        if (++spins < SPIN_LIMIT) {
            _mm_pause();
            continue;
        }
        // Sleep after a long idle spell so an idle process stops burning its cores
        uint32_t e = atomic_load_explicit(&pool.epoch, memory_order_acquire);
        atomic_fetch_add(&pool.sleepers, 1);
        if ((uint32_t)(atomic_load(&pool.ticket) >> 32) == last)
            syscall(SYS_futex, &pool.epoch, FUTEX_WAIT_PRIVATE, e, NULL, NULL, 0);
        atomic_fetch_sub(&pool.sleepers, 1);
        spins = 0;
    }
    return NULL;
}

// Start the workers once using the thread count asked for but never more than the cores allowed
static void start_pool(void)
{
    const char *env = getenv("COUNTDOWN_THREADS");
    long want = env ? strtol(env, NULL, 10) : 8;
    cpu_set_t set;
    if (sched_getaffinity(0, sizeof set, &set) == 0 && CPU_COUNT(&set) < want)
        want = CPU_COUNT(&set);
    if (want < 1)
        want = 1;
    if (want > MAX_THREADS)
        want = MAX_THREADS;
    pool.threads = (unsigned)want;
    for (unsigned t = 1; t < pool.threads; t++) {
        pthread_t id;
        pthread_attr_t attr;
        pthread_attr_init(&attr);
        pthread_attr_setdetachstate(&attr, PTHREAD_CREATE_DETACHED);
        if (pthread_create(&id, &attr, worker, (void *)(uintptr_t)t) != 0) {
            perror("pthread_create");
            exit(2);
        }
        pthread_attr_destroy(&attr);
    }
}

// Run fn over every item sharing them with the workers when shared is set and wait for all to finish
static void run(state *s, job_fn fn, unsigned items, bool shared)
{
    if (!shared || pool.threads < 2 || items < 2) {
        for (unsigned i = 0; i < items; i++)
            fn(s, i, 0);
        return;
    }
    uint32_t g = ++pool.gen;
    pool.slot[g & 1].fn = fn;
    pool.slot[g & 1].s = s;
    atomic_store_explicit(&pool.slot[g & 1].items, items, memory_order_relaxed);
    atomic_store_explicit(&pool.done, 0, memory_order_relaxed);
    atomic_store_explicit(&pool.ticket, (uint64_t)g << 32, memory_order_release);
    atomic_fetch_add_explicit(&pool.epoch, 1, memory_order_release);
    if (atomic_load(&pool.sleepers))
        syscall(SYS_futex, &pool.epoch, FUTEX_WAKE_PRIVATE, INT_MAX, NULL, NULL, 0);
    work(g, 0);
    while (atomic_load_explicit(&pool.done, memory_order_acquire) != items)
        _mm_pause();
}

// Write two words as an entry so the compiler emits two plain stores
static inline void store(entry *e, uint64_t head, uint64_t operands)
{
    memcpy(e, &head, 8);
    memcpy((char *)e + 8, &operands, 8);
}

// Return the operator and masks of an entry shifted above its value
static inline uint64_t template(uint8_t op, unsigned larger_mask, unsigned smaller_mask)
{
    return (uint64_t)(op | larger_mask << 8 | smaller_mask << 16) << 32;
}

// Return x divided by y rounded to the nearest integer using the reciprocal of y
static inline uint32_t quotient(uint32_t x, double inv)
{
    return (uint32_t)_mm_cvtsd_si32(_mm_set_sd((double)x * inv));
}

// Append a value advancing past it only if the bitset shows it is new so duplicates cost no mispredicted branch
#define EMIT(v, tmpl)                                                                              \
    do {                                                                                           \
        uint32_t v_ = (v);                                                                         \
        uint64_t word_ = seen[v_ >> 6];                                                            \
        seen[v_ >> 6] = word_ | 1ull << (v_ & 63);                                                 \
        store(out, (tmpl) | v_, operands);                                                         \
        out += ~word_ >> (v_ & 63) & 1;                                                            \
    } while (0)

// Keep a value as the split's best if it is closer to the target or equally close and lower
#define CHECK(v, tmpl)                                                                             \
    do {                                                                                           \
        uint32_t v_ = (v);                                                                         \
        uint32_t d_ = v_ > target ? v_ - target : target - v_;                                     \
        if (v_ && (d_ < whole_distance || (d_ == whole_distance && v_ < (uint32_t)whole_head))) {  \
            whole_distance = d_;                                                                   \
            whole_head = (tmpl) | v_;                                                              \
            whole_operands = operands;                                                             \
        }                                                                                          \
    } while (0)

// Pass every legal value from x and y under Countdown rules to act where x is at least y and inv is 1/y
#define OPS(act, x, y, inv, t)                                                                     \
    do {                                                                                           \
        uint32_t x_ = (x), y_ = (y);                                                               \
        uint64_t operands = x_ | (uint64_t)y_ << 32;                                               \
        act(x_ + y_, t[0]);                                                                        \
        /* Skip a zero result since every intermediate value must be a positive integer */         \
        if (x_ != y_)                                                                              \
            act(x_ - y_, t[1]);                                                                    \
        /* Skip multiplying and dividing by one as they never produce a new value */               \
        if (y_ != 1) {                                                                             \
            act(x_ * y_, t[2]);                                                                    \
            /* Emit zero for an inexact division since bit 0 stays set so it is dropped */         \
            uint32_t q_ = quotient(x_, inv);                                                       \
            act(q_ * y_ == x_ ? q_ : 0, t[3]);                                                     \
        }                                                                                          \
    } while (0)

// Pass every legal combination of each left value with each right value to act using one thread's scratch
#define PAIRS(s, sc, left, right, act)                                                             \
    do {                                                                                           \
        uint64_t tl_[4] = {template(OP_ADD, left, right), template(OP_SUB, left, right),           \
                           template(OP_MUL, left, right), template(OP_DIV, left, right)};          \
        uint64_t tr_[4] = {template(OP_ADD, right, left), template(OP_SUB, right, left),           \
                           template(OP_MUL, right, left), template(OP_DIV, right, left)};          \
        const entry *lefts_ = (s)->arena + (s)->off[left];                                         \
        uint32_t nl_ = (s)->len[left], nr_ = (s)->len[right];                                      \
        const entry *rights_ = (s)->arena + (s)->off[right];                                       \
        /* Invert each right value once per split rather than once per pair */                    \
        uint32_t *rv_ = (sc)->right_values;                                                        \
        double *ri_ = (sc)->right_inv;                                                             \
        for (uint32_t j = 0; j < nr_; j++) {                                                       \
            rv_[j] = rights_[j].value;                                                             \
            ri_[j] = 1.0 / rv_[j];                                                                 \
        }                                                                                          \
        for (uint32_t i = 0; i < nl_; i++) {                                                       \
            uint32_t a_ = lefts_[i].value, j = 0;                                                  \
            for (; j < nr_ && rv_[j] <= a_; j++)                                                   \
                OPS(act, a_, rv_[j], ri_[j], tl_);                                                 \
            double ia_ = 1.0 / a_;                                                                 \
            for (; j < nr_; j++)                                                                   \
                OPS(act, rv_[j], a_, ia_, tr_);                                                    \
        }                                                                                          \
    } while (0)

// Return the entry holding value among n sorted entries or null when it is absent
static inline const entry *lookup(const entry *base, uint32_t n, uint32_t value)
{
    // Skip the search when the value lies outside the subset's range
    if (!n || value < base[0].value || value > base[n - 1].value)
        return NULL;
    // Halve the range with a conditional move so unpredictable comparisons cost no mispredicted branch
    while (n > 1) {
        uint32_t half = n / 2;
        base += (base[half].value <= value) * half;
        n -= half;
    }
    return base->value == value ? base : NULL;
}

// Fill m and op with every number that combines with n under Countdown rules to make the target in operator order
static inline int partners(uint32_t n, uint32_t target, uint32_t m[6], uint8_t op[6])
{
    int count = 0;
    if (target > n)
        m[count] = target - n, op[count++] = OP_ADD;
    if (n > target)
        m[count] = n - target, op[count++] = OP_SUB;
    m[count] = n + target, op[count++] = OP_SUB;
    // Divide only when the quotient could be at least two since neither operand may be one
    if (n != 1 && 2 * n <= target && target % n == 0)
        m[count] = target / n, op[count++] = OP_MUL;
    if (n >= 2 * target && n % target == 0)
        m[count] = n / target, op[count++] = OP_DIV;
    // Skip a product too large for any subset to make
    if (n != 1 && (uint64_t)n * target <= UINT32_MAX)
        m[count] = n * target, op[count++] = OP_DIV;
    return count;
}

// Find how the target is first made from a subset without building all of its values
static bool find_exact(const state *s, unsigned mask, entry *hit)
{
    for (unsigned left = (mask - 1) & mask; left; left = (left - 1) & mask) {
        unsigned right = mask ^ left;
        // Visit splits in the same order as building so the same origin wins
        if (left >= right)
            continue;
        const entry *lefts = s->arena + s->off[left], *rights = s->arena + s->off[right];
        uint32_t nl = s->len[left], nr = s->len[right];
        // Keep the lowest pair as building would since partners come in operator order
        uint32_t best_a = UINT32_MAX, best_b = UINT32_MAX;
        uint8_t best_op = 0;
        uint32_t m[6];
        uint8_t op[6];
        if (nl <= nr) {
            // Take the first left value with any partner on the right since left values ascend
            for (uint32_t i = 0; i < nl && best_op == 0; i++) {
                int count = partners(lefts[i].value, s->target, m, op);
                for (int k = 0; k < count; k++) {
                    if (m[k] < best_b && lookup(rights, nr, m[k])) {
                        best_a = lefts[i].value, best_b = m[k], best_op = op[k];
                    }
                }
            }
        } else {
            for (uint32_t j = 0; j < nr; j++) {
                int count = partners(rights[j].value, s->target, m, op);
                for (int k = 0; k < count; k++) {
                    if (m[k] < best_a && lookup(lefts, nl, m[k])) {
                        best_a = m[k], best_b = rights[j].value, best_op = op[k];
                    }
                }
            }
        }
        if (best_op) {
            bool a_larger = best_a >= best_b;
            *hit = (entry){
                .value = s->target,
                .op = best_op,
                .larger = a_larger ? best_a : best_b,
                .smaller = a_larger ? best_b : best_a,
                .larger_mask = a_larger ? left : right,
                .smaller_mask = a_larger ? right : left,
            };
            return true;
        }
    }
    return false;
}

// Search one subset of the level unless a lower subset has already made the target
static void search_job(state *s, unsigned item, unsigned thread)
{
    (void)thread;
    if (item > atomic_load_explicit(&s->found, memory_order_relaxed))
        return;
    if (!find_exact(s, s->masks[item], &s->hits[item]))
        return;
    // Lower the found index so later subsets of the level can skip their search
    unsigned seen = atomic_load_explicit(&s->found, memory_order_relaxed);
    while (item < seen &&
           !atomic_compare_exchange_weak_explicit(&s->found, &seen, item, memory_order_relaxed, memory_order_relaxed))
        ;
}

// Make a thread's bitset and its ranks cover every value up to largest
static void reserve_seen(scratch *sc, uint32_t largest)
{
    size_t words = largest / 64 + 1;
    if (words <= sc->seen_words)
        return;
    // Replace rather than copy since building leaves the bitset clear
    free(sc->seen);
    free(sc->rank);
    sc->seen = calloc(words, sizeof *sc->seen);
    sc->rank = malloc(words * sizeof *sc->rank);
    if (!sc->seen || !sc->rank) {
        perror("alloc");
        exit(2);
    }
    sc->seen_words = words;
}

// Make room in a thread's scratch for the values and reciprocals of the largest subset built so far
static void reserve_rights(scratch *sc, size_t biggest)
{
    size_t cap = sc->right_cap;
    sc->right_values = grow(sc->right_values, &sc->right_cap, biggest, sizeof *sc->right_values);
    if (sc->right_cap != cap || !sc->right_inv) {
        sc->right_inv = realloc(sc->right_inv, sc->right_cap * sizeof *sc->right_inv);
        if (!sc->right_inv) {
            perror("realloc");
            exit(2);
        }
    }
}

// Build one subset's sorted reachable values into space reserved in the arena keeping the first way to make each
static void build_job(state *s, unsigned item, unsigned thread)
{
    unsigned mask = s->masks[item];
    scratch *sc = &s->scr[thread];
    reserve_seen(sc, s->largest);
    reserve_rights(sc, s->biggest);
    uint64_t *seen = sc->seen;
    size_t count = 0;
    // Mark zero as seen so inexact divisions never become entries
    seen[0] |= 1;
    for (unsigned left = (mask - 1) & mask; left; left = (left - 1) & mask) {
        unsigned right = mask ^ left;
        // Visit each split once rather than once per ordering
        if (left >= right)
            continue;
        // Reserve room for every pair's results plus the one slot each store may write past the end
        size_t pairs = 4 * (size_t)s->len[left] * s->len[right];
        size_t bound = s->max[mask];
        sc->tmp = grow(sc->tmp, &sc->tmp_cap, count + (pairs < bound ? pairs : bound) + 1, sizeof *sc->tmp);
        entry *out = sc->tmp + count;
        PAIRS(s, sc, left, right, EMIT);
        count = out - sc->tmp;
    }
    seen[0] &= ~1ull;

    size_t at;
    if (s->shared) {
        at = atomic_fetch_add_explicit(&s->top, count, memory_order_relaxed);
    } else {
        // Grow the arena as each subset is built when no other thread is reading it
        at = atomic_load_explicit(&s->top, memory_order_relaxed);
        s->arena = grow(s->arena, &s->cap, at + count, sizeof *s->arena);
        atomic_store_explicit(&s->top, at + count, memory_order_relaxed);
    }
    entry *sorted = s->arena + at;
    if (count < RANK_MIN) {
        // Clear only the words this subset touched and insertion sort the few values
        for (size_t i = 0; i < count; i++) {
            entry e = sc->tmp[i];
            seen[e.value >> 6] = 0;
            size_t k = i;
            for (; k > 0 && sorted[k - 1].value > e.value; k--)
                sorted[k] = sorted[k - 1];
            sorted[k] = e;
        }
    } else {
        // Place each value at its rank in the bitset which needs no comparisons
        uint32_t words = s->max[mask] / 64 + 1, below = 0;
        for (uint32_t w = 0; w < words; w++) {
            sc->rank[w] = below;
            below += (uint32_t)__builtin_popcountll(seen[w]);
        }
        for (size_t i = 0; i < count; i++) {
            uint32_t v = sc->tmp[i].value;
            uint64_t lower = _bzhi_u64(seen[v >> 6], v & 63);
            sorted[sc->rank[v >> 6] + __builtin_popcountll(lower)] = sc->tmp[i];
        }
        memset(seen, 0, words * sizeof *seen);
    }
    s->off[mask] = (uint32_t)at;
    s->len[mask] = (uint32_t)count;
}

// Find one split's closest whole-pool value keeping the first way made among equally close lower values
static void closest_job(state *s, unsigned item, unsigned thread)
{
    unsigned k = s->split_order[item], left = s->splits[k], full = s->full;
    scratch *sc = &s->scr[thread];
    reserve_rights(sc, s->biggest);
    uint32_t target = s->target, whole_distance = UINT32_MAX;
    uint64_t whole_head = UINT32_MAX, whole_operands = 0;
    PAIRS(s, sc, left, full ^ left, CHECK);
    s->near[k] = (closest){whole_distance, whole_head, whole_operands};
}

// Return the pair count of a subset's splits which estimates the work of building it
static size_t pair_count(const state *s, unsigned mask)
{
    size_t pairs = 0;
    for (unsigned left = (mask - 1) & mask; left; left = (left - 1) & mask) {
        if (left < (mask ^ left))
            pairs += (size_t)s->len[left] * s->len[mask ^ left];
    }
    return pairs;
}

// Return the values a search of a subset scans which is the shorter half of every split
static size_t scan_count(const state *s, unsigned mask)
{
    size_t scan = 0;
    for (unsigned left = (mask - 1) & mask; left; left = (left - 1) & mask) {
        unsigned right = mask ^ left;
        if (left < right)
            scan += s->len[left] < s->len[right] ? s->len[left] : s->len[right];
    }
    return scan;
}

// Return the largest count of values held by any subset smaller than size
static size_t biggest_below(const state *s, unsigned size)
{
    size_t biggest = 0;
    for (unsigned mask = 1; mask <= s->full; mask++) {
        if ((unsigned)__builtin_popcount(mask) < size && s->len[mask] > biggest)
            biggest = s->len[mask];
    }
    return biggest;
}

static uint32_t distance(uint32_t value, uint32_t target)
{
    return value > target ? value - target : target - value;
}

// Write n in decimal and return the new end
static char *put_uint(char *out, uint32_t n)
{
    char digits[10];
    int k = 0;
    do
        digits[k++] = (char)('0' + n % 10);
    while (n /= 10);
    while (k)
        *out++ = digits[--k];
    return out;
}

// Write the expression for an entry following its origins back to the pool and return the new end
static char *render(const state *s, const entry *e, char *out, bool bracket)
{
    if (!e->op)
        return put_uint(out, e->value);
    if (bracket)
        *out++ = '(';
    out = render(s, lookup(s->arena + s->off[e->larger_mask], s->len[e->larger_mask], e->larger), out, true);
    *out++ = ' ';
    *out++ = (char)e->op;
    *out++ = ' ';
    out = render(s, lookup(s->arena + s->off[e->smaller_mask], s->len[e->smaller_mask], e->smaller), out, true);
    if (bracket)
        *out++ = ')';
    return out;
}

unsigned solve(unsigned target, const unsigned *pool_numbers, unsigned n, char *out)
{
    pthread_once(&pool_once, start_pool);
    state *s = calloc(1, sizeof *s);
    if (!s) {
        perror("calloc");
        exit(2);
    }
    s->scr = calloc(pool.threads, sizeof *s->scr);
    if (!s->scr) {
        perror("calloc");
        exit(2);
    }
    s->target = target;
    s->full = (1u << n) - 1;

    // Work out each subset's largest value since subtracting and dividing never exceed the larger operand
    uint32_t largest[10] = {0};
    for (unsigned mask = 1; mask <= s->full; mask++) {
        if (!(mask & (mask - 1))) {
            s->max[mask] = pool_numbers[__builtin_ctz(mask)];
        } else {
            for (unsigned left = (mask - 1) & mask; left; left = (left - 1) & mask) {
                uint64_t a = s->max[left], b = s->max[mask ^ left];
                uint64_t m = a * b > a + b ? a * b : a + b;
                s->max[mask] = m > s->max[mask] ? (uint32_t)m : s->max[mask];
            }
        }
        // Track the largest value of each size so each bitset only grows when bigger subsets are built
        unsigned size = (unsigned)__builtin_popcount(mask);
        if (s->max[mask] > largest[size])
            largest[size] = s->max[mask];
    }

    // Store each pool number as a one-number subset
    s->arena = grow(NULL, &s->cap, 4096, sizeof *s->arena);
    const entry *best = NULL;
    for (unsigned i = 0; i < n; i++) {
        s->arena[i] = (entry){.value = pool_numbers[i]};
        s->off[1u << i] = i;
        s->len[1u << i] = 1;
        if (!best && pool_numbers[i] == target)
            best = &s->arena[i];
    }
    atomic_store_explicit(&s->top, n, memory_order_relaxed);

    // List subsets by size then mask so each level's subsets sit together in canonical order
    uint8_t order[256];
    unsigned first[10] = {0};
    for (unsigned mask = 1; mask <= s->full; mask++)
        first[__builtin_popcount(mask) + 1]++;
    for (unsigned size = 1; size <= n + 1; size++)
        first[size] += first[size - 1];
    unsigned fill[10];
    memcpy(fill, first, sizeof fill);
    for (unsigned mask = 1; mask <= s->full; mask++)
        order[fill[__builtin_popcount(mask)]++] = (uint8_t)mask;

    // Work through subsets smallest first stopping at the first size that hits the target
    for (unsigned size = 2; size <= n && !best; size++) {
        unsigned count = first[size + 1] - first[size];
        // Estimate the work only for levels big enough to share
        bool threads = pool.threads > 1 && size >= FROM_SIZE;
        s->masks = order + first[size];
        size_t scan = 0;
        for (unsigned k = 0; threads && k < count; k++)
            scan += scan_count(s, s->masks[k]);
        // Keep the lowest matching subset of this size to break ties the same way every run
        if (scan >= SEARCH_MIN) {
            atomic_store_explicit(&s->found, UINT_MAX, memory_order_relaxed);
            run(s, search_job, count, true);
            unsigned found = atomic_load_explicit(&s->found, memory_order_relaxed);
            if (found != UINT_MAX)
                best = &s->hits[found];
        } else {
            for (unsigned k = 0; k < count && !best; k++) {
                if (find_exact(s, s->masks[k], &s->hits[k]))
                    best = &s->hits[k];
            }
        }
        // Skip building the whole pool's values since no larger subset is made from them
        if (best || size == n)
            break;
        s->largest = largest[size];
        s->biggest = biggest_below(s, size);
        size_t pairs = 0;
        for (unsigned k = 0; threads && k < count; k++)
            pairs += pair_count(s, s->masks[k]);
        s->shared = pairs >= BUILD_MIN;
        if (!s->shared) {
            for (unsigned k = 0; k < count; k++)
                build_job(s, k, 0);
            continue;
        }
        // Order the level's subsets by work so the largest start first and the threads finish together
        uint8_t sorted[256];
        size_t work[256], room = 0;
        for (unsigned k = 0; k < count; k++) {
            unsigned mask = s->masks[k];
            work[k] = pair_count(s, mask);
            room += 4 * work[k] < s->max[mask] ? 4 * work[k] : s->max[mask];
            unsigned j = k;
            for (; j > 0 && work[j - 1] < work[k]; j--)
                sorted[j] = sorted[j - 1];
            sorted[j] = (uint8_t)mask;
            size_t w = work[k];
            for (unsigned i = k; i > j; i--)
                work[i] = work[i - 1];
            work[j] = w;
        }
        s->masks = sorted;
        // Reserve the level's arena space up front since threads read lower levels while others append
        s->arena = grow(s->arena, &s->cap, atomic_load_explicit(&s->top, memory_order_relaxed) + room + 1,
                        sizeof *s->arena);
        run(s, build_job, count, true);
        s->shared = false;
    }

    entry whole;
    if (!best) {
        // Rank by distance from the target then by how many numbers are used so the simplest answer wins
        uint32_t best_distance = UINT32_MAX;
        int best_used = 99;
        // Include a one-number pool here since the whole-pool pass below needs at least two numbers
        unsigned last = n > 1 ? s->full - 1 : s->full;
        for (unsigned mask = 1; mask <= last; mask++) {
            int used = __builtin_popcount(mask);
            const entry *values = s->arena + s->off[mask];
            for (uint32_t i = 0; i < s->len[mask]; i++) {
                uint32_t d = distance(values[i].value, target);
                if (d < best_distance || (d == best_distance && used < best_used))
                    best = &values[i], best_distance = d, best_used = used;
            }
        }
        // Check the whole pool's values as they are made since no larger subset is built from them
        if (n > 1) {
            unsigned full = s->full, splits = 0;
            size_t work[64];
            for (unsigned left = (full - 1) & full; left; left = (left - 1) & full) {
                if (left < (full ^ left)) {
                    work[splits] = (size_t)s->len[left] * s->len[full ^ left];
                    s->splits[splits] = left;
                    s->split_order[splits] = (uint8_t)splits;
                    splits++;
                }
            }
            // Start the splits with the most pairs first so the threads finish together
            for (unsigned k = 1; k < splits; k++) {
                uint8_t j = s->split_order[k];
                unsigned i = k;
                for (; i > 0 && work[s->split_order[i - 1]] < work[j]; i--)
                    s->split_order[i] = s->split_order[i - 1];
                s->split_order[i] = j;
            }
            s->biggest = biggest_below(s, n);
            run(s, closest_job, splits, true);
            // Combine the splits in canonical order so the first way made wins among equally close values
            uint32_t whole_distance = UINT32_MAX;
            uint64_t whole_head = UINT32_MAX, whole_operands = 0;
            for (unsigned k = 0; k < splits; k++) {
                closest c = s->near[k];
                if (c.distance < whole_distance ||
                    (c.distance == whole_distance && (uint32_t)c.head < (uint32_t)whole_head)) {
                    whole_distance = c.distance;
                    whole_head = c.head;
                    whole_operands = c.operands;
                }
            }
            // Fall back to the whole pool only when it gets strictly closer as it uses the most numbers
            if (whole_distance < best_distance) {
                store(&whole, whole_head, whole_operands);
                best = &whole;
            }
        }
    }

    // Render without outer brackets which matches stripping them from the bracketed form
    *render(s, best, out, false) = '\0';
    unsigned value = best->value;
    free(s->arena);
    for (unsigned t = 0; t < pool.threads; t++) {
        scratch *sc = &s->scr[t];
        free(sc->tmp);
        free(sc->seen);
        free(sc->rank);
        free(sc->right_values);
        free(sc->right_inv);
    }
    free(s->scr);
    free(s);
    return value;
}
