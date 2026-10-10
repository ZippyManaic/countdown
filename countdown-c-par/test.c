// Check the dealer in every mode and the solver against rounds with known answers

#include <stdio.h>
#include <string.h>

#include "round.h"
#include "solver.h"

static int failures;

static void expect(int ok, const char *what)
{
    if (!ok) {
        fprintf(stderr, "FAIL: %s\n", what);
        failures++;
    }
}

// Check one dealt round and return its large count, or -1 when it breaks the rules
static int check_round(enum mode mode, unsigned target, const unsigned pool[6])
{
    if (target < 100 || target > 999)
        return -1;
    const unsigned *cards = large_numbers(mode);
    unsigned small_seen[11] = {0}, large_seen[4] = {0};
    int large = 0;
    for (unsigned i = 0; i < 6; i++) {
        if (pool[i] >= 1 && pool[i] <= 10) {
            // Reject a small number after a large one since the pool lists small cards first
            if (large || ++small_seen[pool[i]] > 2)
                return -1;
            continue;
        }
        unsigned k = 0;
        while (k < 4 && cards[k] != pool[i])
            k++;
        if (k == 4 || large_seen[k]++)
            return -1;
        large++;
    }
    return large;
}

static void check_modes(void)
{
    static const char *const names[3] = {"standard", "cats", "nasty"};
    for (int m = MODE_STANDARD; m <= MODE_NASTY; m++) {
        int seen[5] = {0}, ok = 1;
        for (int r = 0; r < 2000; r++) {
            unsigned pool[6];
            unsigned target = deal_round((enum mode)m, RANDOM_LARGE, pool);
            int large = check_round((enum mode)m, target, pool);
            if (large < 0)
                ok = 0;
            else
                seen[large]++;
        }
        int counts_ok = m == MODE_STANDARD ? !seen[0] && seen[1] && seen[2] && !seen[3] && !seen[4]
                                           : seen[0] && seen[1] && seen[2] && seen[3] && seen[4];
        expect(ok, names[m]);
        expect(counts_ok, names[m]);
        if (m == MODE_STANDARD)
            continue;
        for (int k = 0; k <= 4; k++) {
            unsigned pool[6];
            unsigned target = deal_round((enum mode)m, k, pool);
            expect(check_round((enum mode)m, target, pool) == k, "deals the fixed large count");
        }
    }
}

// Return whether the arguments parse, setting the mode and count they give
static int parses(int argc, char **argv, enum mode *mode, int *large_count)
{
    return parse_args(argc, argv, mode, large_count) == 0;
}

static void check_args(void)
{
    enum mode mode;
    int large_count;
    expect(parses(0, NULL, &mode, &large_count) && mode == MODE_STANDARD && large_count == RANDOM_LARGE,
           "parses no arguments");
    expect(parses(2, (char *[]){"nasty", "4"}, &mode, &large_count) && mode == MODE_NASTY && large_count == 4,
           "parses nasty 4");
    expect(parses(2, (char *[]){"cats", "0"}, &mode, &large_count) && mode == MODE_CATS && large_count == 0,
           "parses cats 0");
    expect(!parses(2, (char *[]){"standard", "3"}, &mode, &large_count), "rejects standard 3");
    expect(!parses(2, (char *[]){"cats", "5"}, &mode, &large_count), "rejects cats 5");
    expect(!parses(1, (char *[]){"dogs"}, &mode, &large_count), "rejects an unknown mode");
    expect(!parses(3, (char *[]){"cats", "1", "2"}, &mode, &large_count), "rejects three arguments");
    expect(!parses(2, (char *[]){"cats", "x"}, &mode, &large_count), "rejects a non-numeric count");
}

int main(void)
{
    char expr[128];
    expect(solve(125, (unsigned[]){1, 5, 7, 3, 75, 50}, 6, expr) == 125 && !strcmp(expr, "75 + 50"),
           "finds simplest solution");
    expect(solve(552, (unsigned[]){8, 4, 2, 5, 100, 25}, 6, expr) == 552, "solves 552");
    unsigned value = solve(974, (unsigned[]){8, 8, 6, 8, 25, 100}, 6, expr);
    expect(value == 973 || value == 975, "reports closest when unsolvable");
    expect(solve(999, (unsigned[]){10, 10, 25, 50, 75, 100}, 6, expr) == 999 &&
               !strcmp(expr, "(((75 + 25) * 100) - 10) / 10"),
           "solves 999 with four large");
    expect(solve(100, (unsigned[]){1, 1, 2, 2, 3, 3}, 6, expr) == 81 &&
               !strcmp(expr, "(((2 + 1) * (2 + 1)) * 3) * 3"),
           "reports closest with no large");
    expect(solve(999, (unsigned[]){2, 3, 87, 62, 37, 12}, 6, expr) == 999 && !strcmp(expr, "37 * ((87 / 3) - 2)"),
           "solves 999 with nasty large numbers");
    check_modes();
    check_args();
    if (!failures)
        puts("all tests passed");
    return failures != 0;
}
