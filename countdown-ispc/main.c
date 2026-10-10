// Generate a Countdown numbers round and work out whether it can be solved

#include <stdio.h>

#include "round.h"
#include "solver.h"

int main(int argc, char **argv)
{
    enum mode mode;
    int large_count;
    if (parse_args(argc - 1, argv + 1, &mode, &large_count)) {
        fprintf(stderr, "%s\n", USAGE);
        return 2;
    }
    unsigned pool[6];
    unsigned target = deal_round(mode, large_count, pool);

    printf("Target: %u\nPool:  ", target);
    for (unsigned i = 0; i < 6; i++)
        printf(" %u", pool[i]);
    putchar('\n');

    char expr[128];
    unsigned value = solve(target, pool, 6, expr);
    if (value == target) {
        printf("Solved: %s = %u\n", expr, value);
        return 0;
    }
    printf("No exact solution, closest is %s = %u (%u away)\n", expr, value,
           value > target ? value - target : target - value);
    return 1;
}
