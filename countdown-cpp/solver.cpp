#include "solver.hpp"

#include <algorithm>
#include <array>
#include <bit>
#include <cstring>
#include <immintrin.h>
#include <limits>
#include <memory>
#include <optional>

namespace countdown {
namespace {

// Sort subsets with fewer values than this by insertion rather than by rank in the bitset
constexpr std::size_t rank_min = 16;

// Record a reachable value with how it was made from the larger and smaller of two values in disjoint subsets
struct Entry {
    // Pack value, operator (zero for a pool number), larger mask and smaller mask from the low bits up
    std::uint64_t head;
    // Pack the larger operand in the low half and the smaller in the high half
    std::uint64_t operands;

    std::uint32_t value() const { return static_cast<std::uint32_t>(head); }
    char op() const { return static_cast<char>(head >> 32); }
    unsigned larger_mask() const { return static_cast<std::uint8_t>(head >> 40); }
    unsigned smaller_mask() const { return static_cast<std::uint8_t>(head >> 48); }
    std::uint32_t larger() const { return static_cast<std::uint32_t>(operands); }
    std::uint32_t smaller() const { return static_cast<std::uint32_t>(operands >> 32); }
};

// Return the operator and masks of an entry shifted above its value
constexpr std::uint64_t make_template(char op, unsigned larger_mask, unsigned smaller_mask)
{
    return std::uint64_t{static_cast<unsigned>(op) | larger_mask << 8 | smaller_mask << 16} << 32;
}

// Hold the four operator templates for one ordering of a split's halves
using Templates = std::array<std::uint64_t, 4>;

constexpr Templates make_templates(unsigned larger_mask, unsigned smaller_mask)
{
    return {make_template('+', larger_mask, smaller_mask), make_template('-', larger_mask, smaller_mask),
            make_template('*', larger_mask, smaller_mask), make_template('/', larger_mask, smaller_mask)};
}

// Return x divided by y rounded to the nearest integer using the reciprocal of y
[[gnu::always_inline]] inline std::uint32_t quotient(std::uint32_t x, double inv)
{
    return static_cast<std::uint32_t>(_mm_cvtsd_si32(_mm_set_sd(static_cast<double>(x) * inv)));
}

// Own an uninitialised array that grows by doubling and keeps a prefix of its contents
template <typename T>
class Buffer {
public:
    T *data() const { return items_.get(); }
    std::size_t capacity() const { return capacity_; }

    void reserve(std::size_t need, std::size_t keep)
    {
        if (need <= capacity_)
            return;
        std::size_t size = std::max<std::size_t>(capacity_, 1024);
        while (size < need)
            size *= 2;
        // Skip zeroing since every slot is written before it is read
        auto grown = std::make_unique_for_overwrite<T[]>(size);
        std::copy_n(items_.get(), keep, grown.get());
        items_ = std::move(grown);
        capacity_ = size;
    }

private:
    std::unique_ptr<T[]> items_;
    std::size_t capacity_ = 0;
};

// Hold the working memory of one solve
struct State {
    std::uint32_t target;
    unsigned full;
    // Keep every subset's sorted values back to back in one arena
    Buffer<Entry> arena;
    std::size_t top = 0;
    std::array<std::uint32_t, 256> off{};
    std::array<std::uint32_t, 256> len{};
    // Hold the largest value each subset can make which bounds the bitset words it touches
    std::array<std::uint32_t, 256> max{};
    // Hold one bit per value seen in the subset being built
    std::unique_ptr<std::uint64_t[]> seen;
    std::size_t seen_words = 0;
    // Collect a subset's new values here before they are sorted into the arena
    Buffer<Entry> tmp;
    // Hold the count of values below each bitset word for ranking
    std::unique_ptr<std::uint32_t[]> rank;
    // Hold the right half's values with their reciprocals for the split being built
    Buffer<std::uint32_t> right_values;
    Buffer<double> right_inv;

    const Entry *values(unsigned mask) const { return arena.data() + off[mask]; }

    // Make the bitset and its ranks cover every value up to largest
    void reserve_seen(std::uint32_t largest)
    {
        std::size_t words = largest / 64 + 1;
        if (words <= seen_words)
            return;
        // Replace rather than copy since building leaves the bitset clear
        seen = std::make_unique<std::uint64_t[]>(words);
        rank = std::make_unique_for_overwrite<std::uint32_t[]>(words);
        seen_words = words;
    }

    // Make room for the values and reciprocals of the largest subset built so far
    void reserve_rights()
    {
        std::size_t biggest = *std::max_element(len.begin() + 1, len.begin() + full + 1);
        right_values.reserve(biggest, 0);
        right_inv.reserve(biggest, 0);
    }
};

// Pass every legal value from x and y under Countdown rules to act where x is at least y and inv is 1/y
template <typename Act>
[[gnu::always_inline]] inline void ops(Act &act, std::uint32_t x, std::uint32_t y, double inv, const Templates &t)
{
    std::uint64_t operands = x | std::uint64_t{y} << 32;
    act(x + y, t[0], operands);
    // Skip a zero result since every intermediate value must be a positive integer
    if (x != y)
        act(x - y, t[1], operands);
    // Skip multiplying and dividing by one as they never produce a new value
    if (y != 1) {
        act(x * y, t[2], operands);
        // Emit zero for an inexact division since bit 0 stays set so it is dropped
        std::uint32_t q = quotient(x, inv);
        act(q * y == x ? q : 0, t[3], operands);
    }
}

// Pass every legal combination of each left value with each right value to act
template <typename Act>
[[gnu::always_inline]] inline void pairs(State &s, unsigned left, unsigned right, Act &act)
{
    const Templates tl = make_templates(left, right), tr = make_templates(right, left);
    const Entry *lefts = s.values(left), *rights = s.values(right);
    std::uint32_t nl = s.len[left], nr = s.len[right];
    // Invert each right value once per split rather than once per pair
    std::uint32_t *rv = s.right_values.data();
    double *ri = s.right_inv.data();
    for (std::uint32_t j = 0; j < nr; j++) {
        rv[j] = rights[j].value();
        ri[j] = 1.0 / rv[j];
    }
    for (std::uint32_t i = 0; i < nl; i++) {
        std::uint32_t a = lefts[i].value(), j = 0;
        // Pair with right values up to a first where a is the larger and ties go left
        for (; j < nr && rv[j] <= a; j++)
            ops(act, a, rv[j], ri[j], tl);
        // Pair with the remaining larger right values where a is the smaller
        double ia = 1.0 / a;
        for (; j < nr; j++)
            ops(act, rv[j], a, ia, tr);
    }
}

// Return the entry holding value among n sorted entries or null when it is absent
[[gnu::always_inline]] inline const Entry *lookup(const Entry *base, std::uint32_t n, std::uint32_t value)
{
    // Skip the search when the value lies outside the subset's range
    if (!n || value < base[0].value() || value > base[n - 1].value())
        return nullptr;
    // Halve the range with arithmetic so unpredictable comparisons cost no mispredicted branch
    while (n > 1) {
        std::uint32_t half = n / 2;
        base += (base[half].value() <= value) * half;
        n -= half;
    }
    return base->value() == value ? base : nullptr;
}

// Pair a number with the operator that combines it with another to make the target
struct Partner {
    std::uint32_t value;
    char op;
};

// Fill buf with every number that combines with n under Countdown rules to make the target in operator order
[[gnu::always_inline]] inline int partners(std::uint32_t n, std::uint32_t target, std::array<Partner, 6> &buf)
{
    int count = 0;
    if (target > n)
        buf[count++] = {target - n, '+'};
    if (n > target)
        buf[count++] = {n - target, '-'};
    buf[count++] = {n + target, '-'};
    // Divide only when the quotient could be at least two since neither operand may be one
    if (n != 1 && 2 * n <= target && target % n == 0)
        buf[count++] = {target / n, '*'};
    if (n >= 2 * target && n % target == 0)
        buf[count++] = {n / target, '/'};
    // Skip a product too large for any subset to make
    if (n != 1 && std::uint64_t{n} * target <= std::numeric_limits<std::uint32_t>::max())
        buf[count++] = {n * target, '/'};
    return count;
}

// Return how the target is first made from a subset without building all of its values
std::optional<Entry> find_exact(const State &s, unsigned mask)
{
    std::array<Partner, 6> buf;
    for (unsigned left = (mask - 1) & mask; left; left = (left - 1) & mask) {
        unsigned right = mask ^ left;
        // Visit splits in the same order as building so the same origin wins
        if (left >= right)
            continue;
        const Entry *lefts = s.values(left), *rights = s.values(right);
        std::uint32_t nl = s.len[left], nr = s.len[right];
        // Keep the lowest pair as building would since partners come in operator order
        std::uint32_t best_a = std::numeric_limits<std::uint32_t>::max(), best_b = best_a;
        char best_op = 0;
        if (nl <= nr) {
            // Take the first left value with any partner on the right since left values ascend
            for (std::uint32_t i = 0; i < nl && !best_op; i++) {
                int count = partners(lefts[i].value(), s.target, buf);
                for (int k = 0; k < count; k++) {
                    if (buf[k].value < best_b && lookup(rights, nr, buf[k].value))
                        best_a = lefts[i].value(), best_b = buf[k].value, best_op = buf[k].op;
                }
            }
        } else {
            for (std::uint32_t j = 0; j < nr; j++) {
                int count = partners(rights[j].value(), s.target, buf);
                for (int k = 0; k < count; k++) {
                    if (buf[k].value < best_a && lookup(lefts, nl, buf[k].value))
                        best_a = buf[k].value, best_b = rights[j].value(), best_op = buf[k].op;
                }
            }
        }
        if (best_op) {
            if (best_a >= best_b)
                return Entry{make_template(best_op, left, right) | s.target, best_a | std::uint64_t{best_b} << 32};
            return Entry{make_template(best_op, right, left) | s.target, best_b | std::uint64_t{best_a} << 32};
        }
    }
    return std::nullopt;
}

// Build the sorted reachable values of a subset into the arena keeping only the first way found to make each
void build(State &s, unsigned mask)
{
    std::uint64_t *seen = s.seen.get();
    std::size_t count = 0;
    // Mark zero as seen so inexact divisions never become entries
    seen[0] |= 1;
    for (unsigned left = (mask - 1) & mask; left; left = (left - 1) & mask) {
        unsigned right = mask ^ left;
        // Visit each split once rather than once per ordering
        if (left >= right)
            continue;
        // Reserve room for every pair's results plus the one slot each store may write past the end
        std::size_t pair_count = 4 * std::size_t{s.len[left]} * s.len[right];
        s.tmp.reserve(count + std::min<std::size_t>(pair_count, s.max[mask]) + 1, count);
        Entry *out = s.tmp.data() + count;
        // Append each value advancing past it only if the bitset shows it is new so duplicates cost no branch
        auto emit = [&](std::uint32_t v, std::uint64_t tmpl, std::uint64_t operands) {
            std::uint64_t word = seen[v >> 6];
            seen[v >> 6] = word | std::uint64_t{1} << (v & 63);
            *out = Entry{tmpl | v, operands};
            out += ~word >> (v & 63) & 1;
        };
        pairs(s, left, right, emit);
        count = static_cast<std::size_t>(out - s.tmp.data());
    }
    seen[0] &= ~std::uint64_t{1};

    s.arena.reserve(s.top + count, s.top);
    const Entry *candidates = s.tmp.data();
    Entry *sorted = s.arena.data() + s.top;
    if (count < rank_min) {
        // Clear only the words this subset touched and insertion sort the few values
        for (std::size_t i = 0; i < count; i++) {
            Entry e = candidates[i];
            seen[e.value() >> 6] = 0;
            std::size_t k = i;
            for (; k > 0 && sorted[k - 1].value() > e.value(); k--)
                sorted[k] = sorted[k - 1];
            sorted[k] = e;
        }
    } else {
        // Place each value at its rank in the bitset which needs no comparisons
        std::uint32_t words = s.max[mask] / 64 + 1, below = 0;
        std::uint32_t *rank = s.rank.get();
        for (std::uint32_t w = 0; w < words; w++) {
            rank[w] = below;
            below += static_cast<std::uint32_t>(std::popcount(seen[w]));
        }
        for (std::size_t i = 0; i < count; i++) {
            std::uint32_t v = candidates[i].value();
            std::uint64_t lower = _bzhi_u64(seen[v >> 6], v & 63);
            sorted[rank[v >> 6] + std::popcount(lower)] = candidates[i];
        }
        std::fill_n(seen, words, 0);
    }
    s.off[mask] = static_cast<std::uint32_t>(s.top);
    s.len[mask] = static_cast<std::uint32_t>(count);
    s.top += count;
}

std::uint32_t distance(std::uint32_t value, std::uint32_t target)
{
    return value > target ? value - target : target - value;
}

// Write n in decimal and return the new end
char *put_uint(char *out, std::uint32_t n)
{
    char digits[10];
    int k = 0;
    do
        digits[k++] = static_cast<char>('0' + n % 10);
    while (n /= 10);
    while (k)
        *out++ = digits[--k];
    return out;
}

// Write the expression for an entry following its origins back to the pool and return the new end
char *render(const State &s, const Entry &e, char *out, bool bracket)
{
    if (!e.op())
        return put_uint(out, e.value());
    if (bracket)
        *out++ = '(';
    out = render(s, *lookup(s.values(e.larger_mask()), s.len[e.larger_mask()], e.larger()), out, true);
    *out++ = ' ';
    *out++ = e.op();
    *out++ = ' ';
    out = render(s, *lookup(s.values(e.smaller_mask()), s.len[e.smaller_mask()], e.smaller()), out, true);
    if (bracket)
        *out++ = ')';
    return out;
}

// Write the simplest expression that hits the target or gets closest into out and return its value
std::uint32_t solve_into(std::uint32_t target, std::span<const std::uint32_t> pool, char *out)
{
    unsigned n = static_cast<unsigned>(pool.size());
    auto state = std::make_unique<State>();
    State &s = *state;
    s.target = target;
    s.full = (1u << n) - 1;

    // Work out each subset's largest value since subtracting and dividing never exceed the larger operand
    std::array<std::uint32_t, 10> largest{};
    for (unsigned mask = 1; mask <= s.full; mask++) {
        if (std::has_single_bit(mask)) {
            s.max[mask] = pool[std::countr_zero(mask)];
        } else {
            for (unsigned left = (mask - 1) & mask; left; left = (left - 1) & mask) {
                std::uint64_t a = s.max[left], b = s.max[mask ^ left];
                s.max[mask] = static_cast<std::uint32_t>(std::max({std::uint64_t{s.max[mask]}, a * b, a + b}));
            }
        }
        // Track the largest value of each size so the bitset only grows when bigger subsets are built
        unsigned size = static_cast<unsigned>(std::popcount(mask));
        largest[size] = std::max(largest[size], s.max[mask]);
    }

    // Store each pool number as a one-number subset
    s.arena.reserve(4096, 0);
    std::optional<Entry> best;
    for (unsigned i = 0; i < n; i++) {
        s.arena.data()[i] = Entry{pool[i], 0};
        s.off[1u << i] = i;
        s.len[1u << i] = 1;
        if (!best && pool[i] == target)
            best = s.arena.data()[i];
    }
    s.top = n;

    // List subsets by size then mask so the loops below need no unpredictable size test
    std::array<std::uint8_t, 256> order;
    std::array<unsigned, 10> first{};
    for (unsigned mask = 1; mask <= s.full; mask++)
        first[std::popcount(mask) + 1]++;
    for (unsigned size = 1; size <= n + 1; size++)
        first[size] += first[size - 1];
    auto fill = first;
    for (unsigned mask = 1; mask <= s.full; mask++)
        order[fill[std::popcount(mask)]++] = static_cast<std::uint8_t>(mask);

    // Work through subsets smallest first stopping at the first size that hits the target
    for (unsigned size = 2; size <= n && !best; size++) {
        // Keep the lowest matching subset of this size to break ties the same way every run
        for (unsigned k = first[size]; k < first[size + 1] && !best; k++)
            best = find_exact(s, order[k]);
        // Skip building the whole pool's values since no larger subset is made from them
        if (best || size == n)
            break;
        s.reserve_rights();
        s.reserve_seen(largest[size]);
        for (unsigned k = first[size]; k < first[size + 1]; k++)
            build(s, order[k]);
    }

    if (!best) {
        // Rank by distance from the target then by how many numbers are used so the simplest answer wins
        std::uint32_t best_distance = std::numeric_limits<std::uint32_t>::max();
        int best_used = 99;
        for (unsigned mask = 1; mask < s.full; mask++) {
            int used = std::popcount(mask);
            const Entry *values = s.values(mask);
            for (std::uint32_t i = 0; i < s.len[mask]; i++) {
                std::uint32_t d = distance(values[i].value(), target);
                if (d < best_distance || (d == best_distance && used < best_used))
                    best = values[i], best_distance = d, best_used = used;
            }
        }
        // Check the whole pool's values as they are made since no larger subset is built from them
        if (n > 1) {
            s.reserve_rights();
            std::uint32_t whole_distance = std::numeric_limits<std::uint32_t>::max();
            Entry whole{std::numeric_limits<std::uint32_t>::max(), 0};
            // Keep a value if it is closer to the target or equally close and lower
            auto check = [&](std::uint32_t v, std::uint64_t tmpl, std::uint64_t operands) {
                std::uint32_t d = distance(v, target);
                if (v && (d < whole_distance || (d == whole_distance && v < whole.value())))
                    whole_distance = d, whole = Entry{tmpl | v, operands};
            };
            for (unsigned left = (s.full - 1) & s.full; left; left = (left - 1) & s.full) {
                if (left < (s.full ^ left))
                    pairs(s, left, s.full ^ left, check);
            }
            // Fall back to the whole pool only when it gets strictly closer as it uses the most numbers
            if (whole_distance < best_distance)
                best = whole;
        }
    }

    // Render without outer brackets which matches stripping them from the bracketed form
    *render(s, *best, out, false) = '\0';
    return best->value();
}

} // namespace

std::pair<std::uint32_t, std::string> solve(std::uint32_t target, std::span<const std::uint32_t> pool)
{
    char expr[128];
    std::uint32_t value = solve_into(target, pool, expr);
    return {value, expr};
}

} // namespace countdown

// Expose the solver with the same C interface as the assembly and C versions so one benchmark harness fits all
extern "C" unsigned solve(unsigned target, const unsigned *pool, unsigned n, char *out)
{
    return countdown::solve_into(target, {pool, n}, out);
}
