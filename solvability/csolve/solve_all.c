// Solve a slice of every pool and target with the reference C solver and write the best values as uint32
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

#include "../../countdown-c/solver.h"

int main(int argc, char **argv)
{
    if (argc != 5 && argc != 6) {
        fprintf(stderr, "usage: solve_all POOLS.txt FIRST END OUT.bin [TEXTS.txt]\n");
        return 2;
    }
    FILE *in = fopen(argv[1], "r");
    FILE *out = fopen(argv[4], "wb");
    if (!in || !out) {
        perror("fopen");
        return 2;
    }
    // Optionally keep each answer's expression so its legality can be checked independently
    FILE *texts = argc == 6 ? fopen(argv[5], "w") : NULL;
    if (argc == 6 && !texts) {
        perror("fopen");
        return 2;
    }
    long first = atol(argv[2]), end = atol(argv[3]);
    unsigned pool[6];
    char text[256];
    for (long index = 0; index < end; index++) {
        if (fscanf(in, "%u %u %u %u %u %u", &pool[0], &pool[1], &pool[2], &pool[3], &pool[4], &pool[5]) != 6) {
            fprintf(stderr, "short pool file at line %ld\n", index + 1);
            return 2;
        }
        if (index < first)
            continue;
        for (unsigned target = 100; target <= 999; target++) {
            uint32_t value = (uint32_t)solve(target, pool, 6, text);
            fwrite(&value, sizeof value, 1, out);
            if (texts)
                fprintf(texts, "%u\t%s\n", value, text);
        }
    }
    fclose(out);
    if (texts)
        fclose(texts);
    return 0;
}
