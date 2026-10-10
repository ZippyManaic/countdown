// Stand in for the x86 intrinsics the C solver uses with portable equivalents for WebAssembly
#ifndef COUNTDOWN_WASM_IMMINTRIN_H
#define COUNTDOWN_WASM_IMMINTRIN_H

#include <stdint.h>

// Hold a scalar double where x86 code would use the low lane of a vector register
typedef double __m128d;

static inline __m128d _mm_set_sd(double x)
{
    return x;
}

// Round to nearest with ties to even as cvtsd2si does under the default rounding mode
static inline int _mm_cvtsd_si32(__m128d x)
{
    // Add 1.5 * 2^52 so the sum holds x rounded in its low bits which is cheaper than a saturating conversion in wasm
    union {
        double d;
        uint64_t u;
    } bits = {.d = x + 6755399441055744.0};
    return (int)(uint32_t)bits.u;
}

// Keep the bits of x below position n which the solver only calls with n below 64
static inline uint64_t _bzhi_u64(uint64_t x, unsigned n)
{
    return x & ((1ull << n) - 1);
}

#endif
