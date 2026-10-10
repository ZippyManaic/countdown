// Prove the branchless binary search finds a value exactly when a plain linear scan does for every sorted list up to N entries
#include "../../../countdown-c/solver.c"

#include <assert.h>

// Bound the list length
#ifndef N
#define N 64
#endif

uint32_t nondet_u32(void);

int main(void)
{
    entry list[N];
    uint32_t n = nondet_u32(), value = nondet_u32();
    __CPROVER_assume(n <= N);
    // Require strictly ascending values as every subset list holds distinct sorted values
    for (uint32_t i = 1; i < n; i++)
        __CPROVER_assume(list[i - 1].value < list[i].value);
    const entry *got = lookup(list, n, value);
    // Find the value the plain way
    const entry *want = NULL;
    for (uint32_t i = 0; i < n; i++)
        if (list[i].value == value)
            want = &list[i];
    assert(got == want);
    return 0;
}
