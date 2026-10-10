// Prove for every cats or nasty-cats pool that solve's subset bounds never truncate and stay inside the reciprocal lemma's range
#include "../../../countdown-c/solver.c"

#include <assert.h>

// Choose the large numbers with -DNASTY for the nasty set
#ifdef NASTY
static const uint32_t LARGE[4] = {12, 37, 62, 87};
#define PROPER_MAX 23949360u
#define WHOLE_MAX 239493600u
#else
#define PROPER_MAX 93750000u
#define WHOLE_MAX 937500000u
static const uint32_t LARGE[4] = {25, 50, 75, 100};
#endif

uint32_t nondet_u32(void);
unsigned nondet_unsigned(void);

#define N 6

int main(void)
{
    // Deal a pool with each small number at most twice and each large number at most once
    unsigned pool[N];
    unsigned used_small[11] = {0}, used_large[4] = {0};
    for (int i = 0; i < N; i++) {
        unsigned k = nondet_unsigned();
        __CPROVER_assume(k < 14);
        if (k < 10) {
            pool[i] = k + 1;
            used_small[k + 1]++;
            __CPROVER_assume(used_small[k + 1] <= 2);
        } else {
            pool[i] = LARGE[k - 10];
            used_large[k - 10]++;
            __CPROVER_assume(used_large[k - 10] <= 1);
        }
    }

    state st = {0};
    state *s = &st;
    unsigned n = N;
    s->full = (1u << n) - 1;
    // Repeat solve's bound computation verbatim
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
        unsigned size = (unsigned)__builtin_popcount(mask);
        if (s->max[mask] > largest[size])
            largest[size] = s->max[mask];
    }

    // Expect every operand the division test sees to lie inside the paper's reciprocal lemma range
    assert(largest[N - 1] < (1u << 27));
    assert(s->max[s->full] < (1u << 30));
    // Confirm the exact worst cases the exhaustive enumeration found so cats_ops can rely on them
    assert(largest[N - 1] <= PROPER_MAX);
    assert(s->max[s->full] <= WHOLE_MAX);

    return 0;
}
