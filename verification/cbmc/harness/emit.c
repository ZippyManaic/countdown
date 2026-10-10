// Prove the branchless EMIT append keeps exactly the first entry for each new nonzero value in order and marks every value in the bitset
#include "../../../countdown-c/solver.c"

#include <assert.h>

// Bound the number of results appended and the values they take
#ifndef K
#define K 24
#endif
#ifndef VMAX
#define VMAX 127u
#endif
#define WORDS (VMAX / 64 + 1)

uint32_t nondet_u32(void);
uint64_t nondet_u64(void);

int main(void)
{
    uint64_t seen[WORDS] = {0};
    entry tmp[K + 1];
    uint32_t vals[K];
    uint64_t tmpls[K], ops[K];
    // Mark zero as seen as build does so inexact divisions are dropped
    seen[0] |= 1;
    entry *out = tmp;
    for (int i = 0; i < K; i++) {
        vals[i] = nondet_u32();
        __CPROVER_assume(vals[i] <= VMAX);
        // Use any operator and masks above the value as template does
        tmpls[i] = nondet_u64() & 0x00ffffff00000000ull;
        ops[i] = nondet_u64();
        uint64_t operands = ops[i];
        EMIT(vals[i], tmpls[i]);
    }
    size_t count = (size_t)(out - tmp);
    // Rebuild the expected list by keeping each nonzero value the first time it appears
    size_t want = 0;
    for (int i = 0; i < K; i++) {
        bool fresh = vals[i] != 0;
        for (int j = 0; j < i; j++)
            if (vals[j] == vals[i])
                fresh = false;
        if (fresh) {
            uint64_t head;
            memcpy(&head, &tmp[want], 8);
            uint64_t operands;
            memcpy(&operands, (char *)&tmp[want] + 8, 8);
            assert(head == (tmpls[i] | vals[i]));
            assert(operands == ops[i]);
            want++;
        }
    }
    assert(count == want);
    // Expect exactly the emitted values and zero to be marked
    uint32_t probe = nondet_u32();
    __CPROVER_assume(probe <= VMAX);
    bool marked = seen[probe >> 6] >> (probe & 63) & 1, emitted = probe == 0;
    for (int i = 0; i < K; i++)
        emitted |= vals[i] == probe;
    assert(marked == emitted);
    return 0;
}
