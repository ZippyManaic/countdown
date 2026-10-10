// Deal Countdown rounds in the standard, cats and nasty-cats modes and read the mode from the command line

#ifndef ROUND_H
#define ROUND_H

enum mode { MODE_STANDARD, MODE_CATS, MODE_NASTY };

// Mark a large count chosen at random rather than fixed on the command line
#define RANDOM_LARGE (-1)

#define USAGE "usage: countdown [standard|cats|nasty] [LARGE]"

// Return the four large cards a mode deals from
const unsigned *large_numbers(enum mode mode);

// Deal a target and six numbers, small first, with large_count large numbers or a random count when it is RANDOM_LARGE
unsigned deal_round(enum mode mode, int large_count, unsigned pool[6]);

// Set the mode and fixed large count from the arguments after the program name and return 0, or return -1 when they are invalid
int parse_args(int argc, char **argv, enum mode *mode, int *large_count);

#endif
