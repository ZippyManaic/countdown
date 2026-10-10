# CBMC checks of the optimised C solver

These harnesses machine-check properties of `countdown-c/solver.c` without changing it. Every CBMC harness
`#include`s the real `solver.c`, so the static functions and macros (`OPS`, `EMIT`, `CHECK`, `PAIRS`,
`lookup`, `partners`, `build`, `quotient`) are the solver's own code, not copies. The one exception is
`harness/rank.c`, which repeats lines 275–285 of `build` word for word because that block cannot be called on
its own.

Tools: CBMC 6.6.0, with CaDiCaL 2.1.3 as an external SAT solver (`--external-sat-solver cadical`). This CBMC
build has no built-in CaDiCaL: `--sat-solver cadical` prints a warning and quietly falls back to MiniSat. Z3
4.13.3 (`--z3`) is used for the reruns. Native checks are built with Clang and `-march=native`.

## Running

```
make            # SAT proofs and native checks, one log per check in logs/
make z3         # rerun the proofs that reach a verdict, using Z3
make slow       # full-range proofs that hit the timeout or memory cap on this machine
```

Every run goes through `cap.sh MEM SECONDS CPUS cmd…`, which runs the command in a `systemd-run --user`
scope with `MemoryMax` and no swap, plus `timeout` and `taskset`. If user scopes are unavailable it falls
back to `prlimit --as`. The defaults are `CAP=6G TIMEOUT=1800 CPUS=20-23`. Each log ends with the wall time
and peak RSS. Results and timings are in `RESULTS.md`.

## The intrinsics model (`shim/immintrin.h`)

CBMC cannot read the x86 intrinsics headers, so `-I shim` puts a model ahead of the system `immintrin.h`.
`_mm_cvtsd_si32` rounds to nearest-even (the default MXCSR mode) and returns `0x80000000` for NaN or
out-of-range inputs, as `cvtsd2si` does. `_bzhi_u64` follows the BMI2 definition, and `_mm_set_sd` puts the
value in the low lane. `native/shim_check.c` compares the model with the real instructions on 22 million
inputs: edge cases, NaN, ±∞, ties and the ±2^31 limits, random bit patterns, and all `bzhi` indices from 0
to 255. Every output matched.

`-DSHIM_ABSTRACT_QUOTIENT` replaces the conversion with "any integer the IEEE error bound allows" (floor or
ceiling of x/y, and exactly x/y when y divides x). This is used only in the experimental integer-half run
of `reciprocal.c`.

## What each check proves

### 1. Reciprocal division test (`harness/reciprocal.c`, `native/recip_exhaustive.c`)

The test is the division arm of `OPS`, with `inv = 1.0 / y` as `PAIRS` computes it:
`q_ = quotient(x_, inv); act(q_ * y_ == x_ ? q_ : 0, …)`.

- **CBMC** (`reciprocal.c`). Let x = q0·y + r0 with 0 ≤ r0 < y, writing the dividend this way so the
  specification needs no divider circuit. For every x in [X_MIN, X_MAX] and y in [max(2, Y_MIN), Y_MAX] with
  y ≤ x, `OPS` offers the division, and the value it passes on is q0 when r0 = 0 and 0 otherwise. In other
  words, the test says "exact" exactly when y divides x, and the quotient it gives is x/y. The defaults cover
  every 32-bit x; the Makefile runs cells. y = 1 is excluded because `OPS` skips it. The float semantics are
  CBMC's IEEE-754 binary64 model with round-to-nearest-even.
- **Native, exhaustive over the whole 32-bit range** (`recip_exhaustive.c`). This compiles the real
  `quotient` and the exact `q_ * y_ == x_ ? q_ : 0` expression. For every divisor y from 2 to 2^32 − 1 and
  every multiple x = k·y ≤ 2^32 − 1, it checks that the test returns k: 91,633,733,620 cases in all. That
  covers the "exact ⇒ correct quotient" half for all inputs. The other half (y ∤ x ⇒ 0) holds for every q:
  q·y ≡ x (mod 2^32) would need q·y = x + m·2^32. That is impossible with m = 0 because y ∤ x, and with
  m ≠ 0 because the rounded product is monotone in x, so the multiples on either side of x bound q to
  [k, k+1], where k = ⌊x/y⌋ and both multiples were checked exactly. Then q·y ∈ [x − y, x + y), which lies
  strictly inside (x − 2^32, x + 2^32). The run also checks the neighbours of the first and last multiple of
  each y. A mutant that rounds the reciprocal to single precision fails 11.4 billion of these cases, so the
  check has teeth.

### 2. Branchless binary search (`harness/lookup.c`, `harness/lookup_order.c`)

- `lookup.c` covers every list of n ≤ N entries with fully symbolic, strictly ascending 32-bit values, and
  every 32-bit key. `lookup` returns exactly the entry a linear scan finds, or NULL when the scan finds
  none. Pointer, bounds and overflow checks are on, and unwinding assertions show the loop bounds suffice.
  Proved for N = 16 in the Makefile; N = 8 and N = 32 were run by hand.
- `lookup_order.c` uses the list 2, 4, 6, … and covers every n ≤ 1024 and every key from 0 to 2N + 3. That
  covers below the first entry, equal to each entry, between each pair and above the last. `lookup` only
  compares the key with entries (`<`, `<=`, `>`, `==`), so its control flow depends only on the key's order
  position, and this list represents every strictly ascending list of that length. That is a
  data-independence argument, not something CBMC checks.

### 3. Append, dedup and sort kernels

- `emit.c`: for any sequence of K = 24 values in [0, 127], with arbitrary templates and operands, appended
  with the real `EMIT` into a bitset with bit 0 pre-set (as `build` does), the output holds exactly one entry
  per distinct nonzero value. It is the first occurrence, in order, and both 8-byte words of the stored entry
  are correct (value | template, operands). Afterwards the bitset marks exactly the emitted values plus zero.
- `rank.c`: for up to C = 20 distinct values in [1, 200] marked in the bitset, the verbatim rank-sort block
  puts every entry at the index equal to the number of smaller values, and leaves the bitset clear.
- `build.c`: whole `build(s, 3)` on two symbolic sorted lists (up to LMAX and RMAX values, each ≤ VMAX),
  compared field by field with a plain reference. The reference walks the pairs in canonical order, keeps
  the first derivation of each value and insertion-sorts the result. Only LMAX = RMAX = 1 is within reach,
  which exercises only the insertion-sort path, and even that runs without unwinding assertions. See
  RESULTS.md for why larger sizes exhaust 6 GB.
- `native/build_exhaustive.c` fills the gap. It runs the real `build` on all 5,400,976 pairs of ascending
  lists of 1–3 values from 1..24 (4,964,258 of them take the rank-sort path) and 20,000 random pairs of up to
  12 values below 60,000, comparing each with the same reference. Entries are compared byte for byte, and the
  bitset must be clear afterwards.

### 4. Cats-mode safety

- `native/bounds.c` enumerates all 13,243 dealable pools for each of cats ({25, 50, 75, 100}, 0–4 large) and
  nasty-cats ({12, 37, 62, 87}). For each pool it runs `solve`'s bound recurrence verbatim and reports the
  largest proper-subset bound, the largest whole-pool bound, and whether any bound would be truncated to 32
  bits.
- `harness/cats_ops.c`: `partners` never overflows and returns 1–6 partners for every value n ≤ 93,750,000
  (the largest proper-subset bound) and every target ≤ 10^9. `CHECK` never overflows for any value
  ≤ 937,500,000. The `EMIT` bitset index `v >> 6` is below the allocated word count for every v up to its
  subset's bound, and the bitset stays under 16 MB.
- `harness/cats_bounds.c` runs the same recurrence on a symbolic pool. It exceeds the 6 GB cap, so the
  native enumeration stands in for it.
- `native/sweep.py` builds the real solver unchanged with ASan, UBSan and `-fsanitize=integer`, which traps
  unsigned wrap and lossy implicit conversions. It solves all 13,243 pools of each mode three ways: a random
  target, the stress target 10^9 (above every reachable value, so every subset is built and the whole pool is
  scanned), and a random target with the pool reversed. That is 39,729 rounds per mode. Each answer must
  parse, use only pool numbers, take only legal steps (positive, exact division) and equal the returned
  value. On every four-large pool plus 150 random pools per mode, it also checks the answer's distance and
  number count against `countdown.py`.

### 5. Memory safety of `solve` for n ≤ 3

Not attempted beyond `build` at 1×1. Two things stand in the way: `grow` allocates untyped 16 KB blocks, and
the pointer fields of `state` are heap pointers. Together they make CBMC lower every entry access to byte
operations over many candidate objects. The sanitised sweep covers `solve` on every cats and nasty-cats
pool instead.

## Assumptions common to all checks

- x86-64 LP64, IEEE binary64 doubles, and the default MXCSR rounding mode. Nothing in the solver changes
  the rounding mode.
- The intrinsics model above, which was checked against the hardware.
- Pools of at most 8 numbers, because masks are `uint8_t`. Cats modes use 6.
- Where a CBMC run uses `--no-unwinding-assertions`, its loop bounds are argued by hand in RESULTS.md and
  are not proved.
