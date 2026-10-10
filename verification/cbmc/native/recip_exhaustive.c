// Check the solver's reciprocal division test at every exact quotient for every divisor from 2 to 2^32 - 1 on the real hardware
#include "../../../countdown-c/solver.c"

#include <pthread.h>

// Split the divisors over this many threads
#ifndef THREADS
#define THREADS 4
#endif

typedef struct {
    int index;
    uint64_t checked, failures;
} job;

// Run the exact division expression of OPS on x and y with the reciprocal computed as PAIRS computes it
static inline uint32_t divide(uint32_t x, uint32_t y, double inv)
{
    uint32_t q_ = quotient(x, inv);
    return q_ * y == x ? q_ : 0;
}

static void *work(void *arg)
{
    job *j = arg;
    // Interleave divisors so every thread gets a fair share of the small ones which have the most multiples
    for (uint64_t y = 2 + (uint64_t)j->index; y <= UINT32_MAX; y += THREADS) {
        uint32_t yy = (uint32_t)y;
#ifdef MUTANT
        // Round the reciprocal to single precision to show the check catches a weaker test
        double inv = (float)(1.0 / yy);
#else
        double inv = 1.0 / yy;
#endif
        uint64_t top = UINT32_MAX / y;
        for (uint64_t k = 1; k <= top; k++) {
            uint32_t x = (uint32_t)(k * y);
            if (divide(x, yy, inv) != k && j->failures++ < 5)
                printf("y = %u x = %u gives %u not %llu\n", yy, x, divide(x, yy, inv), (unsigned long long)k);
        }
        j->checked += top;
        // Check the neighbours of the first and last multiples which must report an inexact division
        if (y > 2) {
            uint32_t x1 = (uint32_t)(y + 1), xl = (uint32_t)(top * y - 1);
            if (divide(x1, yy, inv) != 0 || (xl >= y && divide(xl, yy, inv) != 0))
                if (j->failures++ < 5)
                    printf("y = %u gives a false exact division next to a multiple\n", yy);
        }
    }
    return NULL;
}

int main(void)
{
    pthread_t threads[THREADS];
    job jobs[THREADS];
    for (int i = 0; i < THREADS; i++) {
        jobs[i] = (job){.index = i};
        pthread_create(&threads[i], NULL, work, &jobs[i]);
    }
    uint64_t checked = 0, failures = 0;
    for (int i = 0; i < THREADS; i++) {
        pthread_join(threads[i], NULL);
        checked += jobs[i].checked, failures += jobs[i].failures;
    }
    printf("%llu exact divisions checked, %llu failures\n", (unsigned long long)checked, (unsigned long long)failures);
    return failures != 0;
}
