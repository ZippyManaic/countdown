// Check the solver against rounds with known answers

#include <stdio.h>
#include <string.h>

#include "solver.h"

static int failures;

static void expect(int ok, const char *what)
{
    if (!ok) {
        fprintf(stderr, "FAIL: %s\n", what);
        failures++;
    }
}

int main(void)
{
    char expr[128];
    expect(solve(125, (unsigned[]){1, 5, 7, 3, 75, 50}, 6, expr) == 125 && !strcmp(expr, "75 + 50"),
           "finds simplest solution");
    expect(solve(552, (unsigned[]){8, 4, 2, 5, 100, 25}, 6, expr) == 552, "solves 552");
    unsigned value = solve(974, (unsigned[]){8, 8, 6, 8, 25, 100}, 6, expr);
    expect(value == 973 || value == 975, "reports closest when unsolvable");
    if (!failures)
        puts("all tests passed");
    return failures != 0;
}
