package main

import (
	"fmt"
	"os"
	"strconv"
	"strings"
	"time"
)

func main() {
	data, _ := os.ReadFile(os.Args[1])
	// Keep rounds in one flat array so the garbage collector has almost nothing of the harness to scan
	var flat []uint32
	for _, f := range strings.Fields(string(data)) {
		n, _ := strconv.Atoi(f)
		flat = append(flat, uint32(n))
	}
	count := len(flat) / 7
	values := make([]uint32, count)
	exprs := make([]byte, 0, 64*count)
	ends := make([]int, count)
	reps := 1
	if len(os.Args) > 3 {
		reps, _ = strconv.Atoi(os.Args[3])
	}
	start := time.Now()
	for range reps {
		exprs = exprs[:0]
		for i := range count {
			r := flat[7*i : 7*i+7]
			v, e := solve(r[0], r[1:])
			values[i] = v
			exprs = append(exprs, e...)
			ends[i] = len(exprs)
		}
	}
	fmt.Fprintf(os.Stderr, "%.4f ms/round\n", float64(time.Since(start).Microseconds())/1000/float64(count*reps))
	var out []byte
	for i := range count {
		if i > 0 {
			out = append(out, '\n')
		}
		begin := 0
		if i > 0 {
			begin = ends[i-1]
		}
		out = strconv.AppendUint(out, uint64(values[i]), 10)
		out = append(out, '\t')
		out = append(out, exprs[begin:ends[i]]...)
	}
	os.WriteFile(os.Args[2], out, 0o644)
}
