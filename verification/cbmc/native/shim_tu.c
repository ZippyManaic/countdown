// Expose the CBMC intrinsic models under plain names so they can be compared with the real instructions
#include <immintrin.h>

int shim_cvtsd_si32(double d)
{
    return _mm_cvtsd_si32(_mm_set_sd(d));
}

unsigned long long shim_bzhi_u64(unsigned long long x, unsigned long long n)
{
    return _bzhi_u64(x, n);
}
