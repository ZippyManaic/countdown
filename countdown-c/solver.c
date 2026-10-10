#include "solver.h"

#include <immintrin.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// Sort subsets with fewer values than this by insertion rather than by rank in the bitset
#define RANK_MIN 16

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

// Hold the working memory of one solve
typedef struct {
    uint32_t target;
    unsigned full;
    // Keep every subset's sorted values back to back in one arena
    entry *arena;
    size_t top, cap;
    uint32_t off[256], len[256];
    // Hold the largest value each subset can make which bounds the bitset words it touches
    uint32_t max[256];
    // Hold one bit per value seen in the subset being built
    uint64_t *seen;
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

// Keep a value as the whole pool's best if it is closer to the target or equally close and lower
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

// Pass every legal combination of each left value with each right value to act
#define PAIRS(s, left, right, act)                                                                 \
    do {                                                                                           \
        uint64_t tl_[4] = {template(OP_ADD, left, right), template(OP_SUB, left, right),           \
                           template(OP_MUL, left, right), template(OP_DIV, left, right)};          \
        uint64_t tr_[4] = {template(OP_ADD, right, left), template(OP_SUB, right, left),           \
                           template(OP_MUL, right, left), template(OP_DIV, right, left)};          \
        const entry *lefts_ = (s)->arena + (s)->off[left];                                         \
        uint32_t nl_ = (s)->len[left], nr_ = (s)->len[right];                                      \
        const entry *rights_ = (s)->arena + (s)->off[right];                                       \
        /* Invert each right value once per split rather than once per pair */                    \
        uint32_t *rv_ = (s)->right_values;                                                         \
        double *ri_ = (s)->right_inv;                                                              \
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

// Build the sorted reachable values of a subset into the arena keeping only the first way found to make each
static void build(state *s, unsigned mask)
{
    uint64_t *seen = s->seen;
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
        s->tmp = grow(s->tmp, &s->tmp_cap, count + (pairs < bound ? pairs : bound) + 1, sizeof *s->tmp);
        entry *out = s->tmp + count;
        PAIRS(s, left, right, EMIT);
        count = out - s->tmp;
    }
    seen[0] &= ~1ull;

    s->arena = grow(s->arena, &s->cap, s->top + count, sizeof *s->arena);
    entry *sorted = s->arena + s->top;
    if (count < RANK_MIN) {
        // Clear only the words this subset touched and insertion sort the few values
        for (size_t i = 0; i < count; i++) {
            entry e = s->tmp[i];
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
            s->rank[w] = below;
            below += (uint32_t)__builtin_popcountll(seen[w]);
        }
        for (size_t i = 0; i < count; i++) {
            uint32_t v = s->tmp[i].value;
            uint64_t lower = _bzhi_u64(seen[v >> 6], v & 63);
            sorted[s->rank[v >> 6] + __builtin_popcountll(lower)] = s->tmp[i];
        }
        memset(seen, 0, words * sizeof *seen);
    }
    s->off[mask] = (uint32_t)s->top;
    s->len[mask] = (uint32_t)count;
    s->top += count;
}

// Make the bitset and its ranks cover every value up to largest
static void reserve_seen(state *s, uint32_t largest)
{
    size_t words = largest / 64 + 1;
    if (words <= s->seen_words)
        return;
    // Replace rather than copy since building leaves the bitset clear
    free(s->seen);
    free(s->rank);
    s->seen = calloc(words, sizeof *s->seen);
    s->rank = malloc(words * sizeof *s->rank);
    if (!s->seen || !s->rank) {
        perror("alloc");
        exit(2);
    }
    s->seen_words = words;
}

// Make room for the values and reciprocals of the largest subset built so far
static void reserve_rights(state *s)
{
    size_t biggest = 0;
    for (unsigned mask = 1; mask <= s->full; mask++)
        biggest = s->len[mask] > biggest ? s->len[mask] : biggest;
    size_t cap = s->right_cap;
    s->right_values = grow(s->right_values, &s->right_cap, biggest, sizeof *s->right_values);
    if (s->right_cap != cap || !s->right_inv) {
        s->right_inv = realloc(s->right_inv, s->right_cap * sizeof *s->right_inv);
        if (!s->right_inv) {
            perror("realloc");
            exit(2);
        }
    }
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

unsigned solve(unsigned target, const unsigned *pool, unsigned n, char *out)
{
    state *s = calloc(1, sizeof *s);
    if (!s) {
        perror("calloc");
        exit(2);
    }
    s->target = target;
    s->full = (1u << n) - 1;

    // Work out each subset's largest value since subtracting and dividing never exceed the larger operand
    uint32_t largest[10] = {0};
    for (unsigned mask = 1; mask <= s->full; mask++) {
        if (!(mask & (mask - 1))) {
            s->max[mask] = pool[__builtin_ctz(mask)];
        } else {
            for (unsigned left = (mask - 1) & mask; left; left = (left - 1) & mask) {
                uint64_t a = s->max[left], b = s->max[mask ^ left];
                uint64_t m = a * b > a + b ? a * b : a + b;
                s->max[mask] = m > s->max[mask] ? (uint32_t)m : s->max[mask];
            }
        }
        // Track the largest value of each size so the bitset only grows when bigger subsets are built
        unsigned size = (unsigned)__builtin_popcount(mask);
        if (s->max[mask] > largest[size])
            largest[size] = s->max[mask];
    }

    // Store each pool number as a one-number subset
    s->arena = grow(NULL, &s->cap, 4096, sizeof *s->arena);
    const entry *best = NULL;
    for (unsigned i = 0; i < n; i++) {
        s->arena[i] = (entry){.value = pool[i]};
        s->off[1u << i] = i;
        s->len[1u << i] = 1;
        if (!best && pool[i] == target)
            best = &s->arena[i];
    }
    s->top = n;

    // List subsets by size then mask so the loops below need no unpredictable size test
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
    entry hit;
    for (unsigned size = 2; size <= n && !best; size++) {
        // Keep the lowest matching subset of this size to break ties the same way every run
        for (unsigned k = first[size]; k < first[size + 1] && !best; k++) {
            if (find_exact(s, order[k], &hit))
                best = &hit;
        }
        // Skip building the whole pool's values since no larger subset is made from them
        if (best || size == n)
            break;
        reserve_rights(s);
        reserve_seen(s, largest[size]);
        for (unsigned k = first[size]; k < first[size + 1]; k++)
            build(s, order[k]);
    }

    entry whole;
    if (!best) {
        // Rank by distance from the target then by how many numbers are used so the simplest answer wins
        uint32_t best_distance = UINT32_MAX;
        int best_used = 99;
        for (unsigned mask = 1; mask < s->full; mask++) {
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
            reserve_rights(s);
            uint32_t whole_distance = UINT32_MAX;
            uint64_t whole_head = UINT32_MAX, whole_operands = 0;
            unsigned full = s->full;
            for (unsigned left = (full - 1) & full; left; left = (left - 1) & full) {
                if (left < (full ^ left))
                    PAIRS(s, left, full ^ left, CHECK);
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
    free(s->tmp);
    free(s->seen);
    free(s->rank);
    free(s->right_values);
    free(s->right_inv);
    free(s);
    return value;
}
