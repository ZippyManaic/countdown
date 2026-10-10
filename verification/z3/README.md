# Z3 cross-checks of the Countdown mathematics

These scripts use Z3 4.13.3 (Python API) to check results from `paper/countdown.tex` and to give a third,
independent "no exact solution" route alongside the exhaustive checker (`solvability/checker`) and the C
solver. Results and timings are in `RESULTS.md`, and the raw per-query output is in `results/`.

| Script | What it checks |
|--------|----------------|
| `lemma_reciprocal.py` | Lemma lem:reciprocal for the exact division test in `countdown-c/solver.c` |
| `prop_prime.py` | Proposition prop:prime as used: no legal final × makes a prime target in 100..999 |
| `prop_max_bound.py` | Propositions prop:max and prop:bound for every expression tree over up to 4 symbolic numbers, plus the one-node lemmas that give both for any pool size by induction |
| `cats_max.py` | The Section sec:cats largest values 937,500,000 and 239,493,600 are reached and never exceeded |
| `no_solution.py` | Exact solvability in unbounded integer arithmetic, compared with `solvability/data/misses*.tsv` |
| `common.py` | Shared encodings: the straight-line program, a plain Python evaluator and the reachability recursion |
| `summarise.py` | Collects `results/*.json*` into `results/summary.json` |

## Running

    ./run_all.sh            # everything except the optional 64-bit widening, a few hours on 4 CPUs
    WIDE=1 ./run_all.sh     # also run the 64-bit widening of the reciprocal test (hours more)

`run_all.sh` runs four job chains, one per CPU 16 to 19, and wraps every process in
`systemd-run --user --scope -p MemoryMax=4G -p MemorySwapMax=0 timeout ... taskset -c N`. Each script
also sets Z3's `memory_max_size` to 3000 MB and a per-query timeout. Individual parts can be run alone, for
example `python3 lemma_reciprocal.py validate` or `python3 no_solution.py worst --shard 0 --shards 3`.

## Encodings

**Reciprocal division.** The C code computes `q = (uint32_t)_mm_cvtsd_si32((double)x * (1.0 / y))` and
accepts when `q * y == x` in `uint32_t`. Two encodings are used.

- *Floating-point theory* (`QF_FPBV`): the expression literally, with 32-bit vectors, `fp.div`, `fp.mul`
  and `fp.to_sbv` in round-to-nearest-even, plus the integer-indefinite result of `cvtsd2si` when out of
  range. Bit-blasting makes the soundness direction (accept implies y | x and q = x / y) tractable, but
  the completeness direction (y | x implies accept) is the multiplier-cancellation pattern
  `(k y) * fl(1/y) ≈ k` that SAT solvers cannot close at 31 bits, so it is only run for growing widths
  until it times out.
- *Integer model* (`QF_NIA`): the same expression with every IEEE round-to-nearest-even step written exactly
  over integers, split by the binades of the operands. `fl(1/y) = m1 / 2^(j+53)` where m1 is the integer
  nearest `2^(j+53) / y` (ties to even), the product is rounded to a 53-bit significand in its own binade,
  and `cvtsd2si` rounds that to an integer and saturates to `INT_MIN`. A separate coverage query per case
  proves the product always falls in one of the binades tried, so no case is vacuous. The model is
  validated against Python doubles and the floating-point encoding on 937 inputs, and a mutation (a
  truncating C cast instead of `cvtsd2si`) is caught with a counterexample that Python confirms.

**Expressions.** `no_solution.py` and `cats_max.py` use a straight-line program over Z3 integers: node
`i < 6` is leaf `i`, node `6 + k` is step `k`, each active step picks two distinct earlier nodes with
one-hot selectors, orders them `x ≥ y ≥ 1`, and applies one of `x + y`, `x − y` (if `x > y`), `x · y`
(if `y ≠ 1`) or `v` with `x = y · v` (if `y ≠ 1`). Every node is consumed at most once, so the steps form
a forest and each dealt number is used at most once. Up to 5 steps covers every expression over 6
numbers. "Some node equals t" being UNSAT means no legal expression over any subset of the pool equals t.
Every SAT model is decoded and re-evaluated by a plain Python evaluator, and the targets are also checked
against a Python implementation of Theorem thm:recursion.

`prop_max_bound.py` instead enumerates tree shapes: every unordered binary tree over every non-empty
subset of up to 4 symbolic leaves, with the operator at each node left free.

## Trust

Z3 UNSAT answers are trusted, not certificate-checked. See `RESULTS.md` for what `proof=True` gives.
