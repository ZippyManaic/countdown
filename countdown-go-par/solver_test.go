package main

import (
	"bufio"
	"os"
	"strconv"
	"strings"
	"testing"
)

func TestFindsSimplestSolution(t *testing.T) {
	if value, expr := solve(125, []uint32{1, 5, 7, 3, 75, 50}); value != 125 || expr != "75 + 50" {
		t.Errorf("got %s = %d", expr, value)
	}
	if value, _ := solve(552, []uint32{8, 4, 2, 5, 100, 25}); value != 552 {
		t.Errorf("got %d", value)
	}
}

func TestReportsClosestWhenUnsolvable(t *testing.T) {
	if value, _ := solve(974, []uint32{8, 8, 6, 8, 25, 100}); distance(value, 974) != 1 {
		t.Errorf("got %d", value)
	}
}

func TestHandlesSmallerPools(t *testing.T) {
	if value, expr := solve(10, []uint32{3, 4}); value != 12 || expr != "4 * 3" {
		t.Errorf("got %s = %d", expr, value)
	}
	if value, expr := solve(10, []uint32{7}); value != 7 || expr != "7" {
		t.Errorf("got %s = %d", expr, value)
	}
}

// TestMatchesReferenceAnswers solves the benchmark rounds and compares every answer with the reference
func TestMatchesReferenceAnswers(t *testing.T) {
	rounds, err := os.Open("../bench/data/rounds1k.txt")
	if err != nil {
		t.Skip("benchmark rounds not found")
	}
	defer rounds.Close()
	ref, _ := os.ReadFile("../bench/data/ref1k.tsv")
	want := strings.Split(strings.TrimRight(string(ref), "\n"), "\n")
	scanner := bufio.NewScanner(rounds)
	for i := 0; scanner.Scan(); i++ {
		var numbers []uint32
		for _, f := range strings.Fields(scanner.Text()) {
			n, _ := strconv.Atoi(f)
			numbers = append(numbers, uint32(n))
		}
		value, expr := solve(numbers[0], numbers[1:])
		if got := strconv.Itoa(int(value)) + "\t" + expr; got != want[i] {
			t.Fatalf("round %d: got %q want %q", i, got, want[i])
		}
	}
}

func TestDealsAValidPool(t *testing.T) {
	for range 1000 {
		target, pool := generateRound()
		if target < 100 || target > 999 || len(pool) != 6 {
			t.Fatalf("bad round %d %v", target, pool)
		}
		large, counts := 0, map[uint32]int{}
		for _, n := range pool {
			if n > 10 {
				large++
			}
			counts[n]++
			if n <= 10 && counts[n] > 2 {
				t.Fatalf("too many %d in %v", n, pool)
			}
		}
		if large != 1 && large != 2 {
			t.Fatalf("bad large count in %v", pool)
		}
	}
}
