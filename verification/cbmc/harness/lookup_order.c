// Prove the branchless binary search finds a value exactly when a plain scan does for every list length up to N and every order position of the key
#include "../../../countdown-c/solver.c"

#include <assert.h>

// Bound the list length
#ifndef N
#define N 4096
#endif

uint32_t nondet_u32(void);

// Use the canonical list 2 4 6 and so on since lookup only compares the key with entries so any strictly ascending list behaves like this one
static entry list[N];

int main(void)
{
    for (uint32_t i = 0; i < N; i++)
        list[i].value = 2 * i + 2;
    uint32_t n = nondet_u32(), value = nondet_u32();
    __CPROVER_assume(n <= N);
    // Cover keys below the first entry equal to each entry between each pair and above the last
    __CPROVER_assume(value <= 2 * N + 3);
    const entry *got = lookup(list, n, value);
    // Give the plain scan's answer which for this list is index value / 2 - 1 when value is even and in range
    const entry *want = value % 2 == 0 && value >= 2 && value <= 2 * n ? &list[value / 2 - 1] : NULL;
    assert(got == want);
    return 0;
}
