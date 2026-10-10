# Results (2026-10-10, CPUs 20–23, memory cap per run as stated)

"SAT" means CBMC 6.6.0 with `--external-sat-solver cadical` (CaDiCaL 2.1.3). "Z3" means `--z3`, with
`--fpa` wherever floats appear. Without `--fpa`, CBMC aborts on `floatbv_round_to_integral` with an
invariant violation. Times are wall-clock seconds and include CPU contention from parallel runs. "Cap"
means the run was killed by the systemd `MemoryMax`, and "timeout" means it hit `timeout`.

## 1. Reciprocal division test

| check | bound | SAT | Z3 |
|---|---|---|---|
| `reciprocal.c` | x ≤ 1000, 2 ≤ y ≤ x | SUCCESSFUL, 5.9–13.7 s | timeout at 960 s (an earlier run with x ≤ 100 took 265 s and succeeded) |
| `reciprocal.c` | 2^30 ≤ y < 2^31, y ≤ x < 2^32 | SUCCESSFUL, 9.2 s | not run |
| `reciprocal.c` | 2^15 ≤ y < 2^16, 2^20 ≤ x < 2^21 | SUCCESSFUL, 68 s alone, 245 s under contention | not run |
| `reciprocal.c` | all 32-bit x, 2 ≤ y ≤ x | timeout at 1800 s | — |
| `reciprocal.c` | y ∈ {2, 3}, all x | timeout at 900 s | — |
| `reciprocal.c` | 2^15 ≤ y < 2^16, all x | timeout at 900 s | — |
| `reciprocal.c` | y ∈ [2, 3] or [2^13, 2^14), x ∈ [2^26, 2^27) | timeout at 900 s (both cells) | — |
| `reciprocal.c -DSHIM_ABSTRACT_QUOTIENT` | all 32-bit x (integer half only) | timeout at 900 s | — |
| `--refine` and in-process MiniSat on the 2^15 × 2^20 cell | | timeout at 600 s | — |
| **native `recip_exhaustive`** | **every y in [2, 2^32), every multiple x = k·y < 2^32** | **91,633,733,620 cases, 0 failures, 33 s on 4 cores** | — |
| native single-precision mutant | same | 11,402,963,587 failures (the check catches a weaker test) | — |

Verdict: the test is exact for every 32-bit dividend with 2 ≤ y ≤ x, not just for x < 2^31 as the paper's
lemma states. There is no boundary inside the `uint32_t` range. The `y != 1` guard in `OPS` is essential:
with y = 1 and x ≥ 2^31, `cvtsd2si` overflows to `0x80000000`. Bit-blasted float multiply and divide make
the full-range SAT proof infeasible within the caps, so full coverage comes from the exhaustive native run
together with the monotonicity argument in README.md.

## 2. Branchless binary search

| check | bound | SAT | Z3 |
|---|---|---|---|
| `lookup.c` (symbolic values) | n ≤ 8 | SUCCESSFUL, 2.6 s | — |
| `lookup.c` | n ≤ 16 | SUCCESSFUL, 14.8 s (17.2 s with `--arrays-uf-always`) | timeout at 960 s |
| `lookup.c` | n ≤ 32 | SUCCESSFUL, 168 s (422–520 s in later contended runs) | — |
| `lookup_order.c` (order-canonical list) | n ≤ 1024, every key position | SUCCESSFUL, 200 s, 2.3 GB | — |
| `lookup_order.c` | n ≤ 1024 with `--unwind 1026` instead of a tight `lookup.0` bound | cap (6 GB) at 12 s | — |
| `lookup_order.c` | n ≤ 65536 | cap (6 GB) at 18 s | — |

## 3. Append, dedup and sort kernels

| check | bound | SAT | Z3 |
|---|---|---|---|
| `emit.c` (real `EMIT`) | 24 appends, values ≤ 127 | SUCCESSFUL, 242 s, 2.8 GB | timeout at 960 s |
| `rank.c` (verbatim block) | ≤ 20 distinct values ≤ 200 | timeout at 1800 s | — |
| `rank.c` | ≤ 8 distinct values ≤ 130 | timeout at 330 s (stopped at the 12:40 time box) | — |
| `build.c` (real `build`) | lists of 1 × 1, values ≤ 12, no unwinding assertions | SUCCESSFUL, 1.5 s | SUCCESSFUL, 1.2 s |
| `build.c` | 1 × 1 with unwinding assertions (CBMC's default) | cap (4 GB) at 8 s | — |
| `build.c` | 1 × 2, 2 × 2, 2 × 3, with or without checks, typed or static buffers | cap (4–6 GB) at 13–500 s | — |
| **native `build_exhaustive`** | **all 5,400,976 pairs of lists of 1–3 values from 1..24 (4,964,258 via the rank sort), plus 20,000 random pairs of up to 12 values < 60,000** | **0 failures, 61 s** | — |

The SAT and Z3 back ends agree on every property where both reached a verdict: `build` 1×1 and `cats_ops`.
There Z3 was faster. Z3 timed out on every harness with wide multiplication, float arithmetic or many
symbolic array writes (reciprocal, lookup, emit).

Why `build` fails in CBMC: `grow` allocates untyped blocks (`realloc(p, *cap * size)`), and `state` holds its
buffers behind heap pointers. CBMC lowers each entry access to `byte_update`/`byte_extract` over every
candidate object. A 1 × 2 run already reaches 155 MB of SSA, with 30,429 byte updates. The loop bounds for
the 1 × 1 run without unwinding assertions are: the pair loops run at most `nl` or `nr` ≤ 1 times; the
insertion and rank loops at most `count` ≤ 4 times; the rank word loop at most `max/64 + 1` ≤ 3 times; and
`grow.0:0` because every buffer is preallocated large enough.

## 4. Cats-mode safety

| check | result |
|---|---|
| `native/bounds.c` (verbatim recurrence, all pools) | cats: 13,243 pools, largest proper-subset bound 93,750,000 (1 10 25 50 75 100), largest whole-pool bound 937,500,000 (10 10 25 50 75 100), no truncation. Nasty-cats: largest proper-subset bound 23,949,360, whole-pool bound **239,493,600** (10 10 12 37 62 87). The brief's ~239,488,800 is slightly off. 0.08 s |
| `cats_ops.c` SAT | SUCCESSFUL, 286 s: `partners` (n ≤ 93.75M, target ≤ 10^9), `CHECK` (v ≤ 937.5M) and the `EMIT` index |
| `cats_ops.c` Z3 | SUCCESSFUL, 0.9 s (agrees) |
| `cats_bounds.c` (symbolic pool) SAT | cap (6 GB) at 109 s (cats) and 184 s (nasty-cats) |
| earlier `cats_arith.c` (pool + `OPS` together) | cap (6 GB) at 100–126 s. A float variant timed out at 1800 s |
| `native/sweep.py` (ASan, UBSan, `-fsanitize=integer`) | cats and nasty-cats: 39,729 rounds each, including target 10^9 to force every build. No sanitiser report, and every answer is legal and equals its value. 260 rounds per mode against `countdown.py`, with 0 differences in distance or numbers used. 62 s |

**Verdict: safe.** Every arithmetic and indexing step stays in range for cats and nasty-cats pools.

- The bound recurrence `(uint32_t)m` never truncates.
- Division operands are values of proper subsets, so they stay ≤ 93,750,000 < 2^27. The paper's 2^27
  premise still holds for the reciprocal test even in cats mode, and the test is exact for all of `uint32_t`
  anyway.
- `x_ * y_` in `OPS` is at most M(L)·M(R) ≤ M(S) ≤ 937,500,000 < 2^32, so there is no wrap.
- Bitsets are sized from `largest[size]` for sizes below n only, at most 1,464,845 words (11.7 MB, plus a
  5.9 MB rank array).
- The packed entry's 32-bit value field and 8-bit masks are not exceeded.
- The 64-byte output buffer suffices: at most 6 three-digit numbers, 5 operators and 8 brackets is 41
  characters.

**Where it would break.** This is code reading, confirmed by a crash in a harness that broke the first
condition.

1. If a proper subset's bound reaches 2^32, then `(uint32_t)m` at line 381 truncates `max[]`. The bitset and
   rank array become undersized and `EMIT` writes out of bounds. The native build test segfaulted when fed
   lists whose bound had been truncated.
2. If a whole-pool bound reaches 2^32, `x_ * y_` at line 119 wraps inside `CHECK`. That gives wrong answers,
   though not memory errors.

Neither can happen with distinct large numbers from either set. It would take, for example, a pool with
repeated large numbers such as 100 100 100 100 75 50.

Speed is the practical cost: a four-large pool with an unreachable target takes about 20 ms against about
0.02 ms for a standard round, mostly calloc and memset of the 11.7 MB bitset.

## 5. Memory safety of `solve` for n ≤ 3

Not done. CBMC cannot handle `build` beyond 1 × 1 within the caps (see section 3). The sanitised native sweep
of every cats and nasty-cats pool stands in for it.

## Runs killed by the memory cap

These were killed at 4–6 GB:

- `lookup_order` with N = 1024 and a loose unwind bound, and with N = 65536.
- `cats_arith` (cats and nasty-cats) and `cats_bounds` (cats and nasty-cats).
- `build` at every size from 1 × 2 up, and at 1 × 1 with unwinding assertions.

None were retried above 6 GB.

## CBMC quirks found on the way

- `--sat-solver cadical` is not compiled into this CBMC; it warns and uses MiniSat.
- CBMC 6.6 turns on `--unwinding-assertions` and malloc-may-fail by default.
- `pgrep -f`/`pkill -f` with a pattern that also appears in the shell's own command line kills the calling
  shell.
