// Read rounds as a target followed by six pool numbers per line and print each answer's value and expression from the real solver
#include <stdio.h>

#include "solver.h"

int main(void)
{
    unsigned target, p[6];
    char expr[128];
    while (scanf("%u %u %u %u %u %u %u", &target, &p[0], &p[1], &p[2], &p[3], &p[4], &p[5]) == 7) {
        unsigned value = solve(target, p, 6, expr);
        printf("%u\t%s\n", value, expr);
    }
    return 0;
}
