// Model the three x86 intrinsics solver.c uses with their documented Intel semantics so CBMC can reason about them
// Define SHIM_ABSTRACT_QUOTIENT to replace the float quotient by the IEEE error bound the reciprocal lemma derives
#ifndef CBMC_SHIM_IMMINTRIN_H
#define CBMC_SHIM_IMMINTRIN_H

#include <stdint.h>

// Hold the two lanes of an SSE2 double vector of which the solver only reads the low one
typedef struct {
    double lo, hi;
} __m128d;

// Put x in the low lane and zero the high lane as movsd does
static inline __m128d _mm_set_sd(double x)
{
    __m128d r = {x, 0.0};
    return r;
}

#ifdef __CPROVER__
// Round to an integer under the default MXCSR mode which is nearest with ties to even
#define SHIM_RINT(d) __CPROVER_round_to_integrald((d), 0)
#else
#include <math.h>
#define SHIM_RINT(d) nearbyint(d)
#endif

#ifdef SHIM_ABSTRACT_QUOTIENT
// Name the floor quotient and remainder of the division under test which the harness sets before calling OPS
extern uint32_t shim_q0, shim_r0;
int shim_nondet_int(void);

// Return any integer the IEEE error bound allows which is the floor or ceiling of x / y and exactly x / y when y divides x
static inline int _mm_cvtsd_si32(__m128d a)
{
    (void)a;
    int q = shim_nondet_int();
    __CPROVER_assume(q == (int)shim_q0 || q == (int)shim_q0 + 1);
    if (shim_r0 == 0)
        __CPROVER_assume(q == (int)shim_q0);
    return q;
}
#else
// Convert the low lane as cvtsd2si does returning the integer indefinite value 0x80000000 for NaN or out of range
static inline int _mm_cvtsd_si32(__m128d a)
{
    double r = SHIM_RINT(a.lo);
    if (!(r >= -2147483648.0 && r <= 2147483647.0))
        return (int)0x80000000u;
    return (int)r;
}
#endif

// Clear the bits of x from the index in the low byte of n upwards as BMI2 bzhi does keeping x whole for indices of 64 or more
static inline uint64_t _bzhi_u64(uint64_t x, uint64_t n)
{
    unsigned i = (unsigned)(n & 0xff);
    return i >= 64 ? x : x & ((1ull << i) - 1);
}

#endif
