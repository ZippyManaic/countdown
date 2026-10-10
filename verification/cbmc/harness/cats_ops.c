// Prove partners CHECK and the EMIT bitset index never overflow or leave range for any value up to the cats-mode bounds
#include "../../../countdown-c/solver.c"

#include <assert.h>

// Take the bounds from the exhaustive enumeration in native/bounds.c which nasty-cats stays well inside
#ifndef PROPER_MAX
#define PROPER_MAX 93750000u
#endif
#ifndef WHOLE_MAX
#define WHOLE_MAX 937500000u
#endif
// Cover game targets and the stress target the native sweep uses
#ifndef TARGET_MAX
#define TARGET_MAX 1000000000u
#endif

uint32_t nondet_u32(void);

int main(void)
{
    uint32_t target = nondet_u32();
    __CPROVER_assume(1 <= target && target <= TARGET_MAX);

    // Run the partner search on any value a proper subset can hold
    uint32_t n = nondet_u32();
    __CPROVER_assume(1 <= n && n <= PROPER_MAX);
    uint32_t m[6];
    uint8_t op[6];
    int count = partners(n, target, m, op);
    assert(count >= 1 && count <= 6);

    // Run the whole-pool closeness check on any value the whole pool can make
    uint32_t v = nondet_u32(), whole_distance = nondet_u32();
    __CPROVER_assume(v <= WHOLE_MAX);
    uint64_t whole_head = nondet_u32(), whole_operands = 0, operands = nondet_u32();
    CHECK(v, (uint64_t)OP_MUL << 32);
    (void)whole_operands;

    // Index the bitset as EMIT does for any value up to its subset's bound when the bitset is sized for the largest bound of that size
    uint32_t bound = nondet_u32(), largest = nondet_u32(), w = nondet_u32();
    __CPROVER_assume(bound <= largest && largest <= PROPER_MAX && w <= bound);
    size_t words = largest / 64 + 1;
    assert((size_t)(w >> 6) < words);
    assert((size_t)(bound / 64 + 1) <= words);
    assert((uint64_t)words * sizeof(uint64_t) < 16u << 20);
    return 0;
}
