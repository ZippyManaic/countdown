# Solvability of Countdown numbers rounds: results

Definitions follow `paper/countdown.tex`: a pool is a multiset of six numbers; a value is reachable if some
legal expression (Definition def:expr, operations of Definition def:ops) over a sub-multiset of the pool has
it; an instance (t, p) is *solvable* (has an exact solution) if t is reachable. "Miss" means not solvable.
All probabilities are exact rationals in lowest terms (Python `fractions`), with decimals.

Deal distribution (Section 2): ℓ ∈ {1, 2} uniform, t uniform on 100..999, and for a pool with k = 6 − ℓ
small numbers with multiplicities c_i

  P(p) = ½ · Π_i C(2, c_i) / C(20, k) · 1 / C(4, ℓ).

`analyse.py` checks that these weights sum to exactly 1 over the 9,498 pools and to ½ over each ℓ.

## 1. Verification: three sources agree on every instance

| Source | Design | Misses |
|--------|--------|-------:|
| `checker/reach.rs` (new, Rust) | per pool, per subset mask, full value sets from every ordered disjoint submask pair | 380,523 |
| `countdown-c/solver.c` `solve()` | reference solver, smallest-subset-first with early exit, bitsets, partner lookup | 380,523 |
| `countdown-table/answers.bin` | PyTorch GPU solver | 380,523 |

Over all 8,548,200 instances there are **0 disagreements** in exact/miss status and **0 disagreements in
the optimal distance d\*** between any two of the three sources (`data/compare.txt`). The C solver and
answers.bin even return the same best value on every instance.

Further checks (`data/verify*.txt`):

- Every one of the 8,167,677 certificates emitted by the checker parses, uses a sub-multiset of the pool,
  has every step legal under Definition def:ops (larger operand first, no zero, no × or ÷ by 1, exact
  division) and evaluates to its target. For every pool the certified targets and the targets listed in
  `misses.tsv` partition 100..999 exactly.
- The same verifier accepts all 8,167,677 exact answers stored in answers.bin, a second independent set of
  certificates for the solvable half.
- The verifier rejects deliberately broken expressions (wrong order, zero intermediate, inexact division,
  × 1, unparenthesised chains, numbers not in the pool).
- The checker enumerates its own pools and finds the same 9,498 as `countdown-table/pools.py`.
- The checker is deterministic: two runs give byte-identical results and certificates.

## 2. Headline results (main game, 1 or 2 large)

**Proposition (exhaustion).** Under the game's distribution,

  P(no exact solution) = **16,970,693 / 837,216,000 ≈ 0.020270387809** (about 1 round in 49.3).

| | P(no exact) exact | decimal |
|---|---|---|
| 1 large | 627,787 / 27,907,200 | 0.022495520869 |
| 2 large | 236,059 / 13,081,500 | 0.018045254749 |
| overall (½ each) | 16,970,693 / 837,216,000 | 0.020270387809 |

Uniform over distinct instances: 380,523 of 8,548,200 = 126,841 / 2,849,400 ≈ 0.044515 (1 large:
255,316 / 5,227,200 ≈ 0.048844; 2 large: 125,207 / 3,321,000 ≈ 0.037702). The uniform-instance fraction
is more than twice the dealt rate because the hard pools (repeated small numbers, two 1s) are the
unlikely ones under the deal.

*Proof sketch.* By Theorem thm:recursion the set of values reachable from p is ∪_S V(S), and V(S) is
determined by the splits of S. The checker computes V(S) for all 63 non-empty S of each pool by literally
evaluating the right-hand side of the recursion (all ordered splits, all operand pairs, the four
operations with their conditions), so a target outside the union is unreachable. That gives the miss set
of every pool; summing P(p)/900 over missed (p, t) gives the probability. The solvable half is
independently certified by explicit expressions that a 100-line evaluator checks; the unsolvable half rests
on the exhaustive search, done by two implementations of different design (checker and countdown-c),
plus agreement with the GPU solver's table.

### Pools

- Expected number of unreachable targets in a dealt pool: 18.24 of 900.
- **1,217 of 9,498 pools reach every target** (614 of 5,808 one-large, 603 of 3,690 two-large), with deal
  probability 21,551 / 77,520 ≈ 0.278006 (0.246001 given 1 large, 0.310010 given 2 large). List:
  `data/perfect_pools.txt`.
- Observation: no pool containing two 1s, and no pool with two repeated small values, reaches every target.

| misses per pool | pools (1 large) | pools (2 large) | all | P(deal such a pool) |
|---|---:|---:|---:|---:|
| 0 | 614 | 603 | 1,217 | 0.278006 |
| 1 | 340 | 228 | 568 | 0.095350 |
| 2–5 | 779 | 655 | 1,434 | 0.196015 |
| 6–10 | 586 | 418 | 1,004 | 0.108844 |
| 11–20 | 712 | 446 | 1,158 | 0.105994 |
| 21–50 | 1,217 | 568 | 1,785 | 0.108876 |
| 51–100 | 773 | 402 | 1,175 | 0.062948 |
| 101–200 | 558 | 269 | 827 | 0.035570 |
| 201–400 | 216 | 92 | 308 | 0.007981 |
| 401–900 | 13 | 9 | 22 | 0.000416 |

Worst pools:

| pool | misses | max distance | M(p) |
|---|---:|---:|---:|
| 1 1 2 2 3 25 | 653 | 324 | 675 |
| 1 1 2 2 50 100 | 621 | 22 | 45,000 |
| 1 1 2 2 25 50 | 576 | 25 | 11,250 |
| 1 1 2 2 50 75 | 575 | 25 | 33,750 |
| 1 1 2 2 4 25 | 571 | 99 | 900 |
| 1 9 9 10 10 100 | 569 | 13 | 900,000 |
| 1 1 9 10 10 100 | 546 | 16 | 180,000 |
| 1 1 2 3 3 25 | 535 | 99 | 900 |

By large set, P(no exact | large set): 25 alone 0.0346, 50 alone 0.0253, 75 alone 0.0155, 100 alone
0.0146; pairs from 0.0123 (75, 100) to 0.0231 (50, 100).

### Distance when there is no exact answer

- E[d\* | no exact] = 20,501,954 / 16,970,693 ≈ 1.208080 (1 large 1.2820, 2 large 1.1159).
- E[d\*] over all rounds = 10,250,977 / 418,608,000 ≈ 0.024488.
- Maximum distance 324, attained only by pool 1 1 2 2 3 25 with target 999 (its largest value is 675).
- P(best answer more than 10 away) ≈ 0.0000402.

| d\* | instances | P(no exact and d\* = d) | P(d\* = d \| no exact) |
|---:|---:|---:|---:|
| 1 | 332,553 | 0.018604748 | 0.917829 |
| 2 | 30,217 | 0.001156648 | 0.057061 |
| 3 | 7,693 | 0.000252235 | 0.012444 |
| 4 | 3,392 | 0.000101477 | 0.005006 |
| 5 | 1,707 | 0.000047138 | 0.002325 |
| 6–10 | 2,859 | 0.000067930 | 0.003351 |
| >10 | 2,102 | 0.000040212 | 0.001984 |

### Targets

Per-target miss probability P(no exact | t) under the deal (`data/targets.tsv`):

- Hardest: 967 (0.11847), 937 (0.11606), 941 (0.11517), 933 (0.11470), 947 (0.11186), 863 (0.11114),
  983 (0.10716), 977 (0.10652), 961 (0.10630), 953 (0.10242). By number of pools missing (uniform over
  pools) the order is 967 (2,058), 941 (2,009), 947 (1,971), 933 (1,943), 937 (1,923).
- **Exactly 14 targets are reachable from every pool**: 100, 101, 102, 104, 105, 106, 111, 114, 119, 125,
  150, 200, 300, 450. The next easiest, 600, is missed by one pool.
- The miss rate rises steeply with t: by hundred 0.00044, 0.00256, 0.00569, 0.00853, 0.01457, 0.02169,
  0.02970, 0.04278, 0.05646 (100s to 900s); 0.0052 below 550 against 0.0354 from 550 up.

## 3. Explaining misses

### (a) Value bound: misses are holes, not out of range

**Proposition (largest value).** For every pool, the largest reachable value M(p) equals B(full) for the
recursion B({i}) = p_i, B(S) = max over splits {L, R} of max(B(L)·B(R), B(L) + B(R)).

*Proof.* Upper bound by induction as in Proposition prop:bound, since every legal result of x ≥ y ≥ 1 is
at most max(xy, x + y). Achievability: with x ≥ y, if y = 1 the maximum x + 1 is made by +, and if
y ≥ 2 then xy ≥ x + y and × is legal; so the maximising tree is legal. Data: M(p) = B(p) on all 9,498
pools (and on all 3,745 extra and 10,393 nasty pools).

Facts:

- The paper's bound Π(p_i + 1) − 1 is at least 3,743 for every game pool (minimum at 1 1 2 2 3 25), so it
  never rules out a target in 100..999 and explains **none** of the misses.
- The true M(p) is below 999 for exactly 3 pools: 1 1 2 2 3 25 (675), 1 1 2 2 4 25 (900),
  1 1 2 3 3 25 (900). Only **522 instances** (probability ≈ 9.35 × 10⁻⁶, 0.046% of misses) are out of
  range; the other **380,001 misses are holes** below M(p).
- Size of reach still predicts misses: P(no exact | pool) is 0.124 for M(p) in [999, 9,999], 0.031 for
  [10⁴, 10⁵), 0.017 for [10⁵, 10⁶) and 0.013 above; by number of distinct reachable values it falls from
  0.325 (under 1,000 values) to 0.0006 (16,000 or more).

### (b) Primes

**Proposition.** If t is prime and t is reachable, then some expression for t has top operation +, − or
÷. *Proof.* Under Definition def:ops a top × combines x ≥ y ≥ 2 and gives a composite xy. ∎
So a prime t is reachable only as a + b, a − b or a / b (and a / b needs a = t·b to be reachable from the
other numbers, which for t ≥ 100 needs a value of at least 2t).

Data (main game):

- P(no exact | t prime) = 44,717 / 1,385,670 ≈ 0.03227 against 0.01800 for composite t (143 primes, 757
  composites); ratio 1.79. Primes are harder in every hundred band (e.g. 900s: 0.0956 vs 0.0501).
- The checker records which reachable targets are reachable *only* by a final multiplication; there are
  none among primes (as the proposition requires). Among composites, forbidding the final multiplication
  would raise the composite miss rate from 0.0180 to **0.0314**, close to the prime rate 0.0323. In the 900s
  it would be 0.0870 against 0.0956 for primes. So the loss of the multiplicative route accounts for most,
  but not all, of the prime penalty.
- The penalty extends to composites without small factors. Mean P(no exact | t) by largest prime factor q:
  q ≤ 10: 0.0035 (95 targets); 11 ≤ q ≤ 50: 0.0131 (344); q > 50 composite: 0.0277 (318); prime: 0.0323
  (143). Of the 50 hardest targets, 20 are prime and 46 have largest prime factor above 50.
  *Conjecture:* the hardness of t is governed mainly by whether t factors as a product of values that the
  pool's sub-multisets reach easily, with primes the extreme case.

### (c) Other structure

- Residues: multiples of 25 are easiest (0.0031), then multiples of 10 (0.0050); even targets 0.0150 vs odd
  0.0256. By last digit: 0: 0.0050, 1: 0.0235, 2: 0.0201, 3: 0.0330, 4: 0.0148, 5: 0.0142, 6: 0.0151,
  7: 0.0337, 8: 0.0198, 9: 0.0235.
- Copies of 1: P(no exact | pool) is 0.0122 with no 1, 0.0211 with one, 0.1273 with two (and no pool with
  two 1s reaches everything).
- Repeated small values: 0.0052 with all small values distinct (981 of 2,268 such pools perfect), 0.0379
  with one repeat, 0.1190 with two repeats (none perfect).
- Largest small number: 0.602 when it is 2, 0.228 when 3, 0.098 when 4, falling to 0.012 when 9 and 0.020
  when 10 (the rise at 10 is not explained here).

## 4. Empirical check

`empirical.py` deals 1,000,000 rounds with `countdown.generate_round` from `countdown.py` under
`random.seed(20261010)` and looks each up in the checker's miss sets:

- 20,365 misses = 0.020365, 95% Wilson interval [0.020090, 0.020644]; the exact 0.020270 lies inside
  (z = +0.67). By ℓ: 1 large 0.022455 [0.022048, 0.022870] vs exact 0.022496; 2 large 0.018274
  [0.017907, 0.018649] vs exact 0.018045. This also confirms that the dealer matches the weights above.
- Benchmark set `bench/data/rounds10k.txt`: **224 misses** by `ref10k.tsv` (207 at d\* = 1, 13 at 2, 2 at
  3, 2 at 4, matching the paper's table), 224 by the checker tables with 0 disagreements in status or
  distance; rate 0.0224 [0.0197, 0.0255], z = +1.51 against the exact value.

## 5. Full television rules ("cats mode"): 0 to 4 large numbers

Pools: ℓ = 0: 2,850; 1: 5,808; 2: 3,690; 3: 840; 4: 55 (13,243 in all, 3,745 new). The checker and
countdown-c agree on all 3,370,500 new instances (0 status and 0 distance disagreements,
`data/compare_cats.txt`); all 2,704,309 checker certificates and all 2,704,309 exact C answers verify, and
every one of the 3,370,500 C expressions (exact or not) is legal and has its reported value.

**Integer widths.** The checker uses u64 with checked arithmetic (no overflow occurred). The largest
reachable values are 518,400 (ℓ = 0), 6,480,000 (1), 60,750,000 (2), 337,500,000 (3) and **937,500,000
(ℓ = 4, pool 10 10 25 50 75 100)**. 36 three-large and 37 four-large pools exceed 2^27 = 134,217,728, so the
paper's remark after Proposition prop:bound (values below 2^27) does not hold for these pools. The C
solver nevertheless did not crash and gave the optimal distance on every one of them, and all its
expressions are legal with the claimed value; this is evidence, not a proof, that its 32-bit values and
reciprocal division remain correct up to 937,500,000.

Given ℓ, the deal is P(p | ℓ) = Π C(2, c_i) / C(20, 6 − ℓ) / C(4, ℓ).

| ℓ | pools | P(no exact \| ℓ) | decimal | uniform instances | decimal | perfect pools | E[d\* \| miss] | max d\* | min M(p) | out of range | holes |
|---|---:|---|---:|---|---:|---:|---:|---:|---:|---:|---:|
| 0 | 2,850 | 2,811,013 / 17,442,000 | 0.161163 | 598,427 / 2,565,000 | 0.233305 | 5 | 24.61 | 918 | 81 | 74,012 | 524,415 |
| 1 | 5,808 | 627,787 / 27,907,200 | 0.022496 | 63,829 / 1,306,800 | 0.048844 | 614 | 1.282 | 324 | 675 | 522 | 254,794 |
| 2 | 3,690 | 236,059 / 13,081,500 | 0.018045 | 125,207 / 3,321,000 | 0.037702 | 603 | 1.116 | 25 | 11,250 | 0 | 125,207 |
| 3 | 840 | 54,029 / 1,026,000 | 0.052660 | 62,029 / 756,000 | 0.082049 | 4 | 1.225 | 75 | 375,000 | 0 | 62,029 |
| 4 | 55 | 16,307 / 171,000 | 0.095363 | 1,147 / 9,900 | 0.115859 | 0 | 1.277 | 16 | 18,750,000 | 0 | 5,735 |

- ℓ uniform on 0..4: P(no exact) = **8,611,669 / 123,120,000 ≈ 0.069945**.
- Two large is the most solvable choice; one large is close; three and four large are worse because the
  fewer small numbers are what fine-tunes a big product (e.g. 4 large: 1 1 25 50 75 100 misses 575 targets).
- Zero large is far the worst: 184 pools have M(p) < 999, 74,012 instances are out of range, and the
  worst pool 1 1 2 2 3 3 (M = 81) reaches no target at all.
- Worst pools: ℓ = 0: 1 1 2 2 3 3 (900 misses), 1 1 2 2 3 4 (899); ℓ = 3: 1 1 2 50 75 100 (672),
  1 1 2 25 50 75 (575); ℓ = 4: 1 1 25 50 75 100 (575), 2 2 25 50 75 100 (355).
- Hardest targets given ℓ: ℓ = 0: 997 (0.631), 947, 983; ℓ = 1: 941 (0.159), 937, 933; ℓ = 2: 967 (0.108),
  983, 977; ℓ = 3: 863 (0.248), 967, 961; ℓ = 4: 839 (0.584), 961, 955. Targets reached by every pool of the
  given ℓ: 0, 25, 36, 57 and 203 for ℓ = 0..4.

Details per ℓ: `data/analysis_cats.txt`; per-pool data: `data/misses_cats.tsv`.

## 6. The "nasty" large cards {12, 37, 62, 87}

Same analysis with the large cards replaced (ℓ = 0 is unchanged). 10,393 pools (5,808 + 3,690 + 840 + 55);
the checker and countdown-c agree on all 9,353,700 instances, all 8,971,475 certificates and exact C
answers verify, and all 9,353,700 C expressions are legal with their reported values. The largest
reachable value is 239,493,600 (pool 10 10 12 37 62 87, = 87·62·37·12·100; nine 4-large and five 3-large
nasty pools exceed 2^27).

| ℓ | P(no exact \| ℓ), standard | decimal | P(no exact \| ℓ), nasty | decimal | nasty easier? |
|---|---|---:|---|---:|---|
| 0 | 2,811,013 / 17,442,000 | 0.161163 | same | 0.161163 | same |
| 1 | 627,787 / 27,907,200 | 0.022496 | 293,059 / 9,302,400 | 0.031504 | **no** |
| 2 | 236,059 / 13,081,500 | 0.018045 | 8,167 / 1,046,520 | 0.007804 | yes |
| 3 | 54,029 / 1,026,000 | 0.052660 | 2,819 / 684,000 | 0.004121 | yes |
| 4 | 16,307 / 171,000 | 0.095363 | 17 / 3,800 | 0.004474 | yes |
| ℓ uniform 1..2 | 16,970,693 / 837,216,000 | 0.020270 | 3,290,891 / 167,443,200 | 0.019654 | yes (ratio 0.970) |
| ℓ uniform 0..4 | 8,611,669 / 123,120,000 | 0.069945 | 17,503,343 / 418,608,000 | 0.041813 | yes (ratio 0.598) |
| ℓ uniform 1..4 | 78,934,061 / 1,674,432,000 | 0.047141 | 20,052,403 / 1,674,432,000 | 0.011976 | yes (ratio 0.254) |

Verdict on the fan-wiki claim: **true for 2, 3 and 4 large and for every averaging convention tested,
false for 1 large.** With one nasty card the miss rate rises from 0.0225 to 0.0315 (12 is a weak single
large number: 16 one-large nasty pools containing 12 have M(p) < 999, the worst, 1 1 2 2 3 12, misses 792
targets and 4,752 one-large instances are out of range). With two or more the nasty cards are much better
than the standard ones: 4 large nasty misses only 501 of 49,500 instances (24 of 55 pools perfect) against
5,735 for the standard cards. Plausibly (conjecture) this is because 25, 50, 75 and 100 share the factor
25 and so make fewer distinct combinations, while 12, 37, 62 and 87 are pairwise far less related. Per
target, the nasty cards are harder on 612 of 900 targets with ℓ = 1 but easier on 782, 825 and 664 targets
for ℓ = 2, 3 and 4.

Details: `data/analysis_nasty.txt`; per-pool data: `data/misses_nasty.tsv` (ℓ = 1..4; ℓ = 0 is in
`misses_cats.tsv`).

## 7. Suggested statements for the paper

1. (Exhaustion) Of the 8,548,200 instances, exactly 380,523 have no exact solution; under the game's
   distribution P(no exact) = 16,970,693 / 837,216,000 ≈ 2.027%, with 627,787 / 27,907,200 ≈ 2.250% for
   one large and 236,059 / 13,081,500 ≈ 1.805% for two. Proof: computer exhaustion via Theorem
   thm:recursion, by two independent programs that agree instance by instance; every solvable instance
   has a checked certificate.
2. (Largest value) M(p) is given by the max(xy, x + y) recursion; for game pools M(p) ≥ 675, and only three
   pools have M(p) < 999, so 99.95% of unsolvable rounds fail on holes, not range.
3. (Primes) A prime target can only be made last by +, − or ÷; primes miss at 1.79 times the composite
   rate, and removing the final × from composites nearly closes that gap (0.0314 vs 0.0323).
4. (Distance) When there is no exact answer, d\* = 1 with probability 0.918 and E[d\*] ≈ 1.208; the worst
   case is d\* = 324 (1 1 2 2 3 25, target 999).
5. (Universal targets) Exactly 14 targets are reachable from every pool.
