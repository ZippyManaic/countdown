// Enumerate every cats and nasty-cats pool and report the largest subset bounds solve computes for them
#include <stdint.h>
#include <stdio.h>

// Repeat solve's bound computation verbatim and return the largest bound of a proper subset and of the whole pool
static void bounds(const unsigned *pool, unsigned n, uint64_t *proper, uint64_t *whole, int *truncated)
{
    uint32_t max[256] = {0};
    unsigned full = (1u << n) - 1;
    *proper = 0;
    for (unsigned mask = 1; mask <= full; mask++) {
        if (!(mask & (mask - 1))) {
            max[mask] = pool[__builtin_ctz(mask)];
        } else {
            for (unsigned left = (mask - 1) & mask; left; left = (left - 1) & mask) {
                uint64_t a = max[left], b = max[mask ^ left];
                uint64_t m = a * b > a + b ? a * b : a + b;
                // Note any bound the solver would truncate to 32 bits
                if (m > UINT32_MAX)
                    *truncated = 1;
                max[mask] = m > max[mask] ? (uint32_t)m : max[mask];
            }
        }
        if (mask != full && max[mask] > *proper)
            *proper = max[mask];
    }
    *whole = max[full];
}

int main(void)
{
    static const unsigned sets[2][4] = {{25, 50, 75, 100}, {12, 37, 62, 87}};
    static const char *names[2] = {"cats", "nasty-cats"};
    for (int set = 0; set < 2; set++) {
        uint64_t worst_proper = 0, worst_whole = 0;
        unsigned pools = 0, wp[6] = {0}, ww[6] = {0};
        int truncated = 0;
        // Choose how many of each small number and which large numbers as a multiset
        unsigned c[10];
        for (unsigned code = 0; code < 59049; code++) {
            unsigned k = code, smalls = 0;
            for (int i = 0; i < 10; i++)
                c[i] = k % 3, k /= 3, smalls += c[i];
            if (smalls > 6)
                continue;
            for (unsigned lm = 0; lm < 16; lm++) {
                if (smalls + (unsigned)__builtin_popcount(lm) != 6)
                    continue;
                unsigned pool[6], n = 0;
                for (int i = 0; i < 10; i++)
                    for (unsigned r = 0; r < c[i]; r++)
                        pool[n++] = (unsigned)i + 1;
                for (int j = 0; j < 4; j++)
                    if (lm >> j & 1)
                        pool[n++] = sets[set][j];
                uint64_t p, w;
                bounds(pool, 6, &p, &w, &truncated);
                pools++;
                if (p > worst_proper)
                    worst_proper = p, __builtin_memcpy(wp, pool, sizeof wp);
                if (w > worst_whole)
                    worst_whole = w, __builtin_memcpy(ww, pool, sizeof ww);
            }
        }
        printf("%s: %u pools, largest proper-subset bound %llu (pool %u %u %u %u %u %u), largest whole-pool bound %llu (pool %u %u %u %u %u %u), truncated %d\n",
               names[set], pools, (unsigned long long)worst_proper, wp[0], wp[1], wp[2], wp[3], wp[4], wp[5],
               (unsigned long long)worst_whole, ww[0], ww[1], ww[2], ww[3], ww[4], ww[5], truncated);
    }
    return 0;
}
