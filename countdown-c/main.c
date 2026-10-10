// Generate a Countdown numbers round and work out whether it can be solved

#include <stdio.h>
#include <stdlib.h>

#include "solver.h"

static const unsigned LARGE_NUMBERS[] = {25, 50, 75, 100};

// Shuffle n numbers in place with Fisher-Yates
static void shuffle(unsigned *items, unsigned n)
{
    for (unsigned i = n - 1; i > 0; i--) {
        unsigned j = arc4random_uniform(i + 1);
        unsigned t = items[i];
        items[i] = items[j];
        items[j] = t;
    }
}

int main(void)
{
    unsigned target = 100 + arc4random_uniform(900);
    unsigned large_count = 1 + arc4random_uniform(2);

    // Hold two cards of each small number to match the game's deck
    unsigned small[20];
    for (unsigned i = 0; i < 20; i++)
        small[i] = i % 10 + 1;
    shuffle(small, 20);
    // Shuffle a copy since each large number appears only once in the game
    unsigned large[4] = {LARGE_NUMBERS[0], LARGE_NUMBERS[1], LARGE_NUMBERS[2], LARGE_NUMBERS[3]};
    shuffle(large, 4);

    unsigned pool[6];
    for (unsigned i = 0; i < 6; i++)
        pool[i] = i < 6 - large_count ? small[i] : large[i - (6 - large_count)];

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
