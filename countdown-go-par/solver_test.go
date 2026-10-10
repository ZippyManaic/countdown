package main

import (
	"bufio"
	"os"
	"slices"
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

func TestReportsALoneNumberAsClosest(t *testing.T) {
	if value, expr := solve(100, []uint32{7}); value != 7 || expr != "7" {
		t.Errorf("got %s = %d", expr, value)
	}
}

func TestSolvesWithALoneNumber(t *testing.T) {
	if value, expr := solve(7, []uint32{7}); value != 7 || expr != "7" {
		t.Errorf("got %s = %d", expr, value)
	}
}

func TestReportsClosestWithTwoNumbers(t *testing.T) {
	if value, expr := solve(100, []uint32{3, 4}); value != 12 || expr != "4 * 3" {
		t.Errorf("got %s = %d", expr, value)
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

// Deal many rounds in a mode and check each is legal and every allowed large count occurs
func checkDeals(t *testing.T, mode string) {
	lo, hi := largeRange(mode)
	seen := map[int]bool{}
	for range 2000 {
		target, pool := generateRound(mode, -1)
		if target < 100 || target > 999 || len(pool) != 6 {
			t.Fatalf("bad round %d %v", target, pool)
		}
		large, counts := 0, map[uint32]int{}
		for _, n := range pool {
			counts[n]++
			if n > 10 {
				large++
				if !slices.Contains(largeNumbers[mode], n) || counts[n] > 1 {
					t.Fatalf("bad large number %d in %v", n, pool)
				}
			} else if counts[n] > 2 {
				t.Fatalf("too many %d in %v", n, pool)
			}
		}
		if large < lo || large > hi {
			t.Fatalf("bad large count in %v", pool)
		}
		seen[large] = true
	}
	for count := lo; count <= hi; count++ {
		if !seen[count] {
			t.Errorf("%s never dealt %d large", mode, count)
		}
	}
}

func TestDealsValidPoolsInEveryMode(t *testing.T) {
	for _, mode := range []string{"standard", "cats", "nasty"} {
		checkDeals(t, mode)
	}
}

func TestDealsAFixedLargeCount(t *testing.T) {
	for _, mode := range []string{"cats", "nasty"} {
		for count := range 5 {
			_, pool := generateRound(mode, count)
			large := 0
			for _, n := range pool {
				if n > 10 {
					large++
				}
			}
			if large != count {
				t.Errorf("%s %d dealt %v", mode, count, pool)
			}
		}
	}
}

func TestParsesValidArguments(t *testing.T) {
	cases := []struct {
		args  []string
		mode  string
		count int
	}{{nil, "standard", -1}, {[]string{"nasty", "4"}, "nasty", 4}, {[]string{"cats", "0"}, "cats", 0}}
	for _, c := range cases {
		if mode, count, ok := parseArgs(c.args); !ok || mode != c.mode || count != c.count {
			t.Errorf("%v gave %s %d %v", c.args, mode, count, ok)
		}
	}
}

func TestRejectsInvalidArguments(t *testing.T) {
	for _, args := range [][]string{{"standard", "3"}, {"cats", "5"}, {"easy"}, {"cats", "1", "2"}, {"cats", "x"}} {
		if _, _, ok := parseArgs(args); ok {
			t.Errorf("%v was accepted", args)
		}
	}
}

func TestSolvesCatsRounds(t *testing.T) {
	cases := []struct {
		target uint32
		pool   []uint32
		value  uint32
		expr   string
	}{
		{999, []uint32{10, 10, 25, 50, 75, 100}, 999, "(((75 + 25) * 100) - 10) / 10"},
		{100, []uint32{1, 1, 2, 2, 3, 3}, 81, "(((2 + 1) * (2 + 1)) * 3) * 3"},
		{999, []uint32{2, 3, 87, 62, 37, 12}, 999, "37 * ((87 / 3) - 2)"},
	}
	for _, c := range cases {
		if value, expr := solve(c.target, c.pool); value != c.value || expr != c.expr {
			t.Errorf("%d %v gave %s = %d", c.target, c.pool, expr, value)
		}
	}
}
