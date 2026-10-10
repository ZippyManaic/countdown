// Prove the reciprocal division test in OPS is exact and returns the true quotient for every dividend and divisor in range
#include "../../../countdown-c/solver.c"

#include <assert.h>

// Bound the dividend which defaults to every 32-bit value
#ifndef X_MIN
#define X_MIN 0u
#endif
#ifndef X_MAX
#define X_MAX 0xffffffffu
#endif
// Bound the divisor so long proofs can be split by range
#ifndef Y_MIN
#define Y_MIN 2u
#endif
#ifndef Y_MAX
#define Y_MAX 0xffffffffu
#endif

// Record every value OPS passes on so the division result which comes last can be read back
#define RECORD(v, t)                                                                               \
    do {                                                                                           \
        last = (v);                                                                                \
        (void)(t);                                                                                 \
        calls++;                                                                                   \
    } while (0)

uint32_t nondet_u32(void);

#ifdef SHIM_ABSTRACT_QUOTIENT
uint32_t shim_q0, shim_r0;
#endif

int main(void)
{
    // Describe the dividend as quotient times divisor plus remainder so the specification needs no divider circuit
    uint32_t q0 = nondet_u32(), r0 = nondet_u32(), y = nondet_u32();
    __CPROVER_assume(Y_MIN <= y && y <= Y_MAX && r0 < y);
    uint64_t wide = (uint64_t)q0 * y + r0;
    __CPROVER_assume(wide <= X_MAX && wide >= X_MIN);
    uint32_t x = (uint32_t)wide;
    // Match the solver which only calls OPS with the larger operand first
    __CPROVER_assume(y <= x);
#ifdef SHIM_ABSTRACT_QUOTIENT
    shim_q0 = q0, shim_r0 = r0;
#endif
    // Compute the reciprocal with the same expression PAIRS uses for each right value and each left value
    double inv = 1.0 / y;
    uint64_t t[4] = {0, 0, 0, 0};
    uint32_t last = 0xdeadbeefu;
    int calls = 0;
    OPS(RECORD, x, y, inv, t);
    // Expect the division to have been offered since the divisor is not one
    assert(calls >= 3);
    if (r0 == 0)
        assert(last == q0);
    else
        assert(last == 0);
    return 0;
}
