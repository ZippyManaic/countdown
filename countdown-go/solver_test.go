package main

import "testing"

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
