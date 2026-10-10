// Deal Countdown rounds in the standard, cats and nasty-cats modes and read the mode from the command line

#include <stdlib.h>
#include <string.h>

#include "round.h"

// Give nasty-cats the large cards of the 2010 specials
static const unsigned LARGE_NUMBERS[3][4] = {{25, 50, 75, 100}, {25, 50, 75, 100}, {12, 37, 62, 87}};
static const char *const MODE_NAMES[3] = {"standard", "cats", "nasty"};

const unsigned *large_numbers(enum mode mode)
{
    return LARGE_NUMBERS[mode];
}

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

unsigned deal_round(enum mode mode, int large_count, unsigned pool[6])
{
    unsigned target = 100 + arc4random_uniform(900);
    if (large_count == RANDOM_LARGE)
        large_count = mode == MODE_STANDARD ? 1 + (int)arc4random_uniform(2) : (int)arc4random_uniform(5);
    unsigned n_small = 6 - (unsigned)large_count;

    // Hold two cards of each small number to match the game's deck
    unsigned small[20];
    for (unsigned i = 0; i < 20; i++)
        small[i] = i % 10 + 1;
    shuffle(small, 20);
    // Shuffle a copy since each large number appears only once in the game
    unsigned large[4];
    memcpy(large, LARGE_NUMBERS[mode], sizeof large);
    shuffle(large, 4);

    for (unsigned i = 0; i < 6; i++)
        pool[i] = i < n_small ? small[i] : large[i - n_small];
    return target;
}

int parse_args(int argc, char **argv, enum mode *mode, int *large_count)
{
    *mode = MODE_STANDARD;
    *large_count = RANDOM_LARGE;
    if (argc > 2)
        return -1;
    if (argc == 0)
        return 0;
    unsigned m = 0;
    while (m < 3 && strcmp(argv[0], MODE_NAMES[m]))
        m++;
    if (m == 3)
        return -1;
    *mode = (enum mode)m;
    if (argc == 1)
        return 0;
    // Accept only a single digit so that signs, spaces and trailing text are rejected
    const char *count = argv[1];
    if (count[0] < '0' || count[0] > '9' || count[1])
        return -1;
    int n = count[0] - '0';
    if (*mode == MODE_STANDARD ? n < 1 || n > 2 : n > 4)
        return -1;
    *large_count = n;
    return 0;
}
