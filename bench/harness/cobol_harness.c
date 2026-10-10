// Time the COBOL solver over a file of rounds after starting the COBOL runtime and write each answer as value tab expression
#define _POSIX_C_SOURCE 199309L
#include <libcob.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

int solve(unsigned *target, unsigned *pool, unsigned *n, char *out, unsigned *value, unsigned *len);

static unsigned r[20000][7], v[20000];
static char e[20000][129];

int main(int argc, char **argv)
{
    cob_init(0, NULL);
    FILE *f = fopen(argv[1], "r");
    int n = 0;
    while (fscanf(f, "%u %u %u %u %u %u %u", &r[n][0], &r[n][1], &r[n][2], &r[n][3], &r[n][4], &r[n][5], &r[n][6]) == 7)
        n++;
    int reps = argc > 3 ? atoi(argv[3]) : 1;
    unsigned six = 6, len;
    struct timespec a, b;
    clock_gettime(CLOCK_MONOTONIC, &a);
    for (int k = 0; k < reps; k++)
        for (int i = 0; i < n; i++)
            solve(&r[i][0], &r[i][1], &six, e[i], &v[i], &len);
    clock_gettime(CLOCK_MONOTONIC, &b);
    double s = (b.tv_sec - a.tv_sec) + (b.tv_nsec - a.tv_nsec) / 1e9;
    fprintf(stderr, "%.4f ms/round\n", s * 1000 / n / reps);
    FILE *o = fopen(argv[2], "w");
    for (int i = 0; i < n; i++)
        fprintf(o, i ? "\n%u\t%s" : "%u\t%s", v[i], e[i]);
    return 0;
}
