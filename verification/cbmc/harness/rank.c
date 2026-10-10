// Prove the popcount rank sort places every distinct value at its rank and clears the bitset using a verbatim copy of the block in build
#include "../../../countdown-c/solver.c"

#include <assert.h>

// Bound the number of distinct values and their size
#ifndef C
#define C 20
#endif
#ifndef VMAX
#define VMAX 200u
#endif
#define WORDS (VMAX / 64 + 1)

uint32_t nondet_u32(void);
uint64_t nondet_u64(void);

int main(void)
{
    static state st;
    state *s = &st;
    uint64_t seen[WORDS] = {0};
    uint32_t rank[WORDS];
    entry tmp[C], sorted[C];
    s->seen = seen, s->rank = rank, s->tmp = tmp;
    unsigned mask = 3;
    s->max[mask] = VMAX;
    size_t count = nondet_u32();
    __CPROVER_assume(count <= C);
    // Fill the staging list with distinct positive values and mark them as EMIT leaves them
    for (size_t i = 0; i < count; i++) {
        tmp[i].value = nondet_u32();
        tmp[i].larger = nondet_u32();
        __CPROVER_assume(1 <= tmp[i].value && tmp[i].value <= VMAX);
        for (size_t j = 0; j < i; j++)
            __CPROVER_assume(tmp[j].value != tmp[i].value);
        seen[tmp[i].value >> 6] |= 1ull << (tmp[i].value & 63);
    }

    // Run lines 275 to 285 of solver.c verbatim
    {
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

    // Expect each value at the index equal to how many values are smaller
    for (size_t i = 0; i < count; i++) {
        size_t smaller = 0;
        for (size_t j = 0; j < count; j++)
            smaller += tmp[j].value < tmp[i].value;
        assert(sorted[smaller].value == tmp[i].value);
        assert(sorted[smaller].larger == tmp[i].larger);
    }
    for (size_t w = 0; w < WORDS; w++)
        assert(seen[w] == 0);
    return 0;
}
