// Generate a Countdown numbers round and work out whether it can be solved
package main

import (
	"fmt"
	"math/rand/v2"
	"os"
	"strings"
)

var largeNumbers = []uint32{25, 50, 75, 100}

// generateRound returns a random target and a pool of six numbers with either one or two large numbers
func generateRound() (uint32, []uint32) {
	target := uint32(100 + rand.IntN(900))
	largeCount := 1 + rand.IntN(2)

	// Hold two cards of each small number to match the game's deck
	small := make([]uint32, 20)
	for i := range small {
		small[i] = uint32(i%10 + 1)
	}
	rand.Shuffle(len(small), func(i, j int) { small[i], small[j] = small[j], small[i] })
	// Shuffle a copy since each large number appears only once in the game
	large := append([]uint32(nil), largeNumbers...)
	rand.Shuffle(len(large), func(i, j int) { large[i], large[j] = large[j], large[i] })

	pool := append(small[:6-largeCount:6-largeCount], large[:largeCount]...)
	return target, pool
}

func main() {
	target, pool := generateRound()
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
