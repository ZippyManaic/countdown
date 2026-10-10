# Z3 cross-check results

Z3 4.13.3 through the Python API on CPUs 16 to 19. Every process ran under `systemd-run --user --scope -p
MemoryMax=4G -p MemorySwapMax=0`, `timeout` and `taskset`, and Z3's `memory_max_size` was 3000 MB.
Nothing came close to the memory caps. The session was time-boxed, so runs still going at 12:40 were stopped
and are recorded below as timeouts with what they covered. Raw output is in `results/`, and
`results/summary.json` collects it.

## Summary

| Check | Result | Time |
|-------|--------|------|
| Exact solvability, worst pool 1 1 2 2 3 25, all 900 targets | 653 UNSAT and 247 SAT, all agree with `misses.tsv` | UNSAT mean 2.9 s (max 7.2 s), SAT mean 0.5 s |
| Target 967 on 100 sampled pools that miss it | 100 UNSAT, all agree | mean 32.6 s, max 90.9 s |
| 4-large cats pool 1 1 25 50 75 100 | **stopped at 12:40**: 827 of 900 targets done (100 to 968), 517 of its 575 misses UNSAT, 310 SAT, all agree | UNSAT mean 21.7 s, SAT mean 2.1 s |
| Cats largest value 937,500,000 (10 10 25 50 75 100) | attained (SAT, witness checked) and not exceeded (UNSAT) | 0.15 s and 104 s |
| Nasty largest value 239,493,600 (10 10 12 37 62 87) | attained and not exceeded | 0.28 s and 141 s |
| Prop. prime, 143 primes in 100..999 | no x ≥ y ≥ 2 with xy = t (143 UNSAT) | 14 s total |
| Prop. max and prop. bound, one-node lemmas (any pool size by induction) | all 6 proved | < 0.01 s each |
| Prop. max and prop. bound, per tree, ≤ 3 symbolic leaves | all 34 cases proved, game ranges and unbounded | game up to 178 s, unbounded ≤ 5.6 s |
| Prop. max, per tree, 4 unbounded leaves | **stopped**: 15 of 37 trees proved (all subsets of size ≤ 2 and 5 of 12 size-3 trees), none open | up to 43 s each |
| Prop. bound, per tree, 4 leaves | **not reached** (stopped before it started) | |
| Lemma reciprocal: encodings validated | 937 inputs, integer model = FP theory = Python doubles | 12 s |
| Lemma reciprocal: mutation (truncating cast) | caught, counterexample k = 2^20, y = 998 confirmed by Python | 0.5 s |
| Lemma reciprocal: completeness, 32-bit, integer model | **stopped**: 258 of 275 binade pairs reached proved, 17 unknown at 20 s; the soundness direction was not reached | 22 min |

No Z3 answer disagreed with the exhaustive tables, the plain Python recursion, or the plain Python evaluator
used on every witness.

## 1. Lemma lem:reciprocal

The C code computes `q = (uint32_t)_mm_cvtsd_si32((double)x * (1.0 / y))` and accepts when `q * y == x` in
`uint32_t`, with every rounding to nearest even.

**Floating-point theory (exact C semantics, 32-bit vectors).** Bit-blasting does not scale here. Even the
whole range with y ∈ {2, 3} returned unknown after 600 s, and so did y = 3 alone with x in one binade. Split
by direction:

- *Soundness* (accept ⇒ q·y = x exactly in 64 bits, so y | x and q = x/y) is easy for fixed y: y = 3 over
  all x < 2^31 took 3.1 s (prototype). The per-binade sweep over all y (`lemma_reciprocal.py fp`) was not run
  in the time box.
- *Completeness* (y | x ⇒ accept with q = x/y) is the multiplier-cancellation pattern `(k·y)·fl(1/y) ≈ k`
  that SAT solvers cannot close. y = 3 with x < 2^16 took 27 s, and y = 3 with x < 2^31 was unknown at 300 s.

**Integer model.** This encodes the same expression with each IEEE round-to-nearest-even step written exactly
in integer arithmetic (fl(1/y) = m1/2^(j+53) with m1 the nearest integer to 2^(j+53)/y, the product rounded
to a 53-bit significand in its binade, cvtsd2si rounding to an integer and saturating to INT_MIN). The cases
are split by binade a of k = x/y and binade j of y. A separate query per case proves that the product always
lies in one of the binades encoded, so a case cannot be proved vacuously.

- Validation: on 937 edge and random inputs, the integer model (solved and shown unique), the FP-theory
  encoding and Python doubles give the same q every time.
- Mutation: replacing cvtsd2si's rounding with truncation (a plain C cast) gives SAT with
  k = 1,048,576 and y = 998, where Python gives 1,048,575. The encoding does find real failures.
- Completeness with 2 ≤ y ≤ x < 2^32, plus y = 1 with x < 2^31. The run reached j = 0..9 (y < 1024) over all
  k binades before it was stopped. 258 of 275 cases are proved, most in under 0.1 s. Earlier spot checks
  covered (a, j) = (20, 9), (29, 2), (15, 15) and (30, 0..1) for soundness, all UNSAT in under 0.1 s. The
  17 unknown cases (20 s limit, 600 s for three of them in an earlier run) are all small numbers: k < 128
  and y < 512, plus (a, j) = (24, 6). Nonlinear arithmetic heuristics struggle exactly where the margin is
  largest. One of them, (5, 5), also failed its coverage query. Cases with j ≥ 10 and the whole soundness
  direction were not reached.
- Boundary: at y = 1 the 32-bit code accepts x = 2^31 (q saturates to 0x80000000, which reads back as 2^31)
  and rejects x = 2^31 + 1. So the lemma's bound x < 2^31 is exactly tight for y = 1. The solver never
  divides by 1, and for y ≥ 2 the quotient stays below 2^31 for every uint32 x. For a 64-bit widening, a hand
  analysis says failures need k ≥ 2^51 and none occur for x < 2^53. A Z3 probe proved binades x ∈ [2^30, 2^33)
  of that widening in about 145 s each before it was stopped. The full sweep is `WIDE=1 ./run_all.sh`.

**Verdict.** No counterexample anywhere. Z3 proves the completeness direction for every divisor below 1024
apart from 17 small cases, and the encodings agree with real hardware semantics on every sample. Z3 did not
prove the lemma over its full range in this session.

## 2. Proposition prop:prime

All 143 primes t in 100..999: `x ≥ y ≥ 2 ∧ xy = t` is UNSAT, 14 s in total. In context, for pool
1 1 2 2 3 25 and the reachable primes 101, 103, 107, 109 and 113, no step of any legal program is a
multiplication with value t (UNSAT, 3 to 5 s each), while t itself is reachable (SAT).

## 3. Propositions prop:max and prop:bound

Write g(x, y) = max(xy, x + y) and B for the split recursion. Six one-node lemmas, proved in unbounded
integers, give both propositions for every pool size by induction on |S|. The induction step is on paper and
not checked by Z3:

1. every legal result of x ≥ y ≥ 1 is ≤ g(x, y);
2. g(x, y) is itself a legal result (attainment);
3. g is monotone in both arguments;
4. g(x, y) > x, so B grows when a number is added and subsets never beat the whole pool;
5. every legal result r has r + 1 ≤ (x + 1)(y + 1);
6. the product bound is monotone.

Per tree shape, with the operator at every node left symbolic and the operand order symbolic, Z3 proved
every case it reached:

| Leaves | Claim | Regime | Trees | Proved | Total time | Max |
|-------:|-------|--------|------:|-------:|-----------:|----:|
| 1–2 | max and bound | game and unbounded | 12 | 12 | 25 s | 12.6 s |
| 3 | max (trees over every subset vs B([3])) | game | 9 | 9 | 524 s | 178 s |
| 3 | max | unbounded | 9 | 9 | 4.5 s | 2.0 s |
| 3 | bound | game | 3 | 3 | 403 s | 172 s |
| 3 | bound | unbounded | 3 | 3 | 5.9 s | 5.6 s |
| 4 | max | unbounded | 37 | 15 (stopped) | 275 s | 43 s |
| 4 | bound | unbounded | 15 | 0 (not reached) | | |

"Game" restricts every leaf to {1..10, 25, 50, 75, 100}. This is harder for Z3 than unbounded positive
integers, which imply it, so the game regime was dropped at 4 leaves. No query returned unknown.

## 4. Cats largest values

With the integer straight-line program (up to 5 steps, every node used at most once):

- 10 10 25 50 75 100: some node = 937,500,000 is SAT, witness `(((100*50)*75)*((10*10)*25))`, checked by
  the Python evaluator. Some node > 937,500,000 is UNSAT (104 s).
- 10 10 12 37 62 87: some node = 239,493,600 is SAT, witness `(((62*10)*(37*12))*(87*10))`. Some node
  > 239,493,600 is UNSAT (141 s).

Both values also equal B([6]) and the maximum of the Python recursion's reachable set.

## 5. A third "no solution" route

`no_solution.py` asks Z3 in unbounded integer arithmetic (no bit widths) whether some node of a straight-line
program over the pool equals t. Steps use + always, − when x > y, × when y ≠ 1 and ÷ via x = y·v when y ≠ 1,
with every value positive. UNSAT means no legal expression over any subset of the pool reaches t. Every SAT
model was decoded and re-evaluated by a plain Python evaluator, and every target was also checked against a
Python implementation of Theorem thm:recursion.

| Instances | Expected (tables) | Z3 | Unknown or timeout | UNSAT time | SAT time |
|-----------|-------------------|----|--------------------|------------|----------|
| 1 1 2 2 3 25, t = 100..999 | 653 miss, 247 solvable | 653 UNSAT, 247 SAT | 0 | mean 2.9 s, median 2.5 s, max 7.2 s | mean 0.5 s, max 5.9 s |
| t = 967, 100 sampled missing pools (seed 967) | 100 miss | 100 UNSAT | 0 | mean 32.6 s, median 29.8 s, max 90.9 s | |
| 1 1 25 50 75 100, t = 100..968 (stopped at 12:40) | 517 miss, 310 solvable in that range | 517 UNSAT, 310 SAT | 0 | mean 21.7 s, max 30.0 s | mean 2.1 s, max 24.9 s |

The cats pool ran for 98 minutes on 2 CPUs before it was stopped. Targets 969 to 999 (58 misses among them)
were not reached. Its full miss count in `misses_cats.tsv` is 575, matching the paper.

Agreement is total: zero disagreements with `misses.tsv` and `misses_cats.tsv`, zero between the tables and
the Python recursion, and zero witnesses rejected by the evaluator.

## Trust statement

- **Z3 UNSAT results are trusted, not certificate-checked.** A bug in Z3's nonlinear integer arithmetic
  (nlsat and the nla solver) or in its FP bit-blaster would go unnoticed. SAT results are checked
  independently, since every witness is re-evaluated outside Z3.
- `proof=True` is not usable as an independent certificate. For one worst-pool instance (t = 179,
  6.5 s with proofs on), Z3 produced a 188 MB proof term with 115,902 `th-lemma` steps, 556,227
  unit resolutions and 708,711 hypotheses. The `th-lemma` steps are theory facts that Z3 asserts and no
  external tool checks. Z3 4.13's `proof.log` and `drat.file` options log clausal steps, but again leave the
  arithmetic lemmas to Z3 itself. So the Z3 route is independent in *design* from the C solver and the
  checker, with different code and a different encoding, but it is not a proof certificate.
- The encodings themselves are trusted modelling. The straight-line program's correspondence to
  Definition def:expr (a forest of at most 5 steps over 6 leaves, single consumption) is argued in
  `README.md`, not proved. The integer model of IEEE rounding is validated against hardware doubles and by
  the mutation test, but it is still a hand encoding.
- The induction steps that lift the one-node lemmas of Section 3 to all pool sizes are on paper only.

## Not done in the time box

The FP-theory soundness sweep by divisor binade, the FP completeness width sweep, the reciprocal integer
model for j ≥ 10 and the whole soundness direction, prop:max on the remaining 22 four-leaf trees,
prop:bound on 4 leaves, cats targets 969 to 999, and the 64-bit widening sweep. `run_all.sh` runs them all
with the full timeouts.
