// Compare the CBMC intrinsic models with the real x86 instructions on edge cases and random inputs
#include <immintrin.h>
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int shim_cvtsd_si32(double d);
unsigned long long shim_bzhi_u64(unsigned long long x, unsigned long long n);

static uint64_t state = 88172645463325252ull;

// Draw a 64-bit pseudo-random number with xorshift
static uint64_t next(void)
{
    state ^= state << 13, state ^= state >> 7, state ^= state << 17;
    return state;
}

static long failures, checks;

static void check_cvt(double d)
{
    int want = _mm_cvtsd_si32(_mm_set_sd(d)), got = shim_cvtsd_si32(d);
    checks++;
    if (want != got && failures++ < 10)
        printf("cvtsd_si32(%a): real %d model %d\n", d, want, got);
}

int main(void)
{
    static const double edges[] = {0.0, -0.0, 0.5, 1.5, 2.5, -0.5, -1.5, 2147483647.0, 2147483647.4, 2147483647.5,
                                   2147483648.0, -2147483648.0, -2147483648.5, -2147483649.0, 4294967295.0, 1e300,
                                   -1e300, INFINITY, -INFINITY, NAN};
    for (size_t i = 0; i < sizeof edges / sizeof *edges; i++)
        check_cvt(edges[i]);
    for (long i = 0; i < 20000000; i++) {
        // Mix arbitrary bit patterns with values near integers in the solver's range
        uint64_t r = next();
        double d;
        if (i & 1)
            memcpy(&d, &r, 8);
        else
            d = (double)(uint32_t)r * ((double)(next() % 4096) / 4096.0 + 0.5) + (double)(r >> 62) * 0.5;
        check_cvt(d);
    }
    for (long i = 0; i < 2000000; i++) {
        unsigned long long x = next(), n = i < 256 ? (unsigned long long)i : next();
        checks++;
        if (_bzhi_u64(x, n) != shim_bzhi_u64(x, n) && failures++ < 10)
            printf("bzhi(%llx, %llu) differs\n", x, n);
    }
    printf("%ld checks, %ld differences\n", checks, failures);
    return failures != 0;
}
