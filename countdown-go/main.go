// Generate a Countdown numbers round and work out whether it can be solved
package main

import (
	"fmt"
	"math/rand/v2"
	"os"
	"slices"
	"strings"
)

// Map each mode to its large cards, with nasty-cats using the cards of the 2010 specials
var largeNumbers = map[string][]uint32{
	"standard": {25, 50, 75, 100},
	"cats":     {25, 50, 75, 100},
	"nasty":    {12, 37, 62, 87},
}

const usage = "usage: countdown [standard|cats|nasty] [LARGE]"

// Return the smallest and largest number of large cards the mode allows
func largeRange(mode string) (int, int) {
	if mode == "standard" {
		return 1, 2
	}
	return 0, 4
}

// Return a random target and six numbers with one or two large in standard mode and none to four otherwise, using largeCount when it is not negative
func generateRound(mode string, largeCount int) (uint32, []uint32) {
	target := uint32(100 + rand.IntN(900))
	if largeCount < 0 {
		lo, hi := largeRange(mode)
		largeCount = lo + rand.IntN(hi-lo+1)
	}

	// Hold two cards of each small number to match the game's deck
	small := make([]uint32, 20)
	for i := range small {
		small[i] = uint32(i%10 + 1)
	}
	rand.Shuffle(len(small), func(i, j int) { small[i], small[j] = small[j], small[i] })
	// Shuffle a copy since each large number appears only once in the game
	large := slices.Clone(largeNumbers[mode])
	rand.Shuffle(len(large), func(i, j int) { large[i], large[j] = large[j], large[i] })

	pool := append(small[:6-largeCount:6-largeCount], large[:largeCount]...)
	return target, pool
}

// Return the mode and fixed large count, or -1 for a random count, and false when the arguments are invalid
func parseArgs(args []string) (string, int, bool) {
	if len(args) > 2 {
		return "", 0, false
	}
	mode := "standard"
	if len(args) > 0 {
		mode = args[0]
	}
	if _, ok := largeNumbers[mode]; !ok {
		return "", 0, false
	}
	if len(args) < 2 {
		return mode, -1, true
	}
	// Accept only a single digit so that forms such as "+1" are rejected as in the Python version
	lo, hi := largeRange(mode)
	if len(args[1]) != 1 || args[1][0] < '0'+byte(lo) || args[1][0] > '0'+byte(hi) {
		return "", 0, false
	}
	return mode, int(args[1][0] - '0'), true
}

func main() {
	mode, largeCount, ok := parseArgs(os.Args[1:])
	if !ok {
		fmt.Fprintln(os.Stderr, usage)
		os.Exit(2)
	}
	target, pool := generateRound(mode, largeCount)
	text := make([]string, len(pool))
	for i, n := range pool {
		text[i] = fmt.Sprint(n)
	}
	fmt.Printf("Target: %d\n", target)
	fmt.Printf("Pool:   %s\n", strings.Join(text, " "))

	value, expr := solve(target, pool)
	if value == target {
		fmt.Printf("Solved: %s = %d\n", expr, value)
		return
	}
	fmt.Printf("No exact solution, closest is %s = %d (%d away)\n", expr, value, distance(value, target))
	os.Exit(1)
}
