// Time a solver exposing the C interface over a file of rounds and write each answer as value tab expression
#define _POSIX_C_SOURCE 199309L
#include <stdlib.h>
#include <stdio.h>
#include <time.h>
unsigned solve(unsigned target, const unsigned *pool, unsigned n, char *out);
static unsigned r[20000][7], v[20000];
static char e[20000][128];
int main(int argc, char **argv) {
    FILE *f = fopen(argv[1], "r");
    int n = 0;
    while (fscanf(f, "%u %u %u %u %u %u %u", &r[n][0], &r[n][1], &r[n][2], &r[n][3], &r[n][4], &r[n][5], &r[n][6]) == 7) n++;
    int reps = argc > 3 ? atoi(argv[3]) : 1;
    struct timespec a, b;
    clock_gettime(CLOCK_MONOTONIC, &a);
    for (int k = 0; k < reps; k++)
        for (int i = 0; i < n; i++) v[i] = solve(r[i][0], &r[i][1], 6, e[i]);
    clock_gettime(CLOCK_MONOTONIC, &b);
    double s = (b.tv_sec - a.tv_sec) + (b.tv_nsec - a.tv_nsec) / 1e9;
    fprintf(stderr, "%.4f ms/round\n", s * 1000 / n / reps);
    FILE *o = fopen(argv[2], "w");
    for (int i = 0; i < n; i++) fprintf(o, i ? "\n%u\t%s" : "%u\t%s", v[i], e[i]);
    return 0;
}
