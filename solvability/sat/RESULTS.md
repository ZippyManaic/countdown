# SAT cross-check: pilot results

Machine: Intel i9-13900HX, CPUs 24 to 31 only (efficiency cores), one solver per CPU, at most six solver
processes at a time, each under `systemd-run --scope -p MemoryMax=4G..6G -p MemorySwapMax=0`, `timeout`
and `taskset`. Times are wall-clock seconds per process on one core; memory is peak RSS. CaDiCaL 2.1.3
(standalone), CaDiCaL 2.1.2 (inside `bv_decide`), Lean 4.34.1, cake_lpr a36874a, lrat-check 2e3b2dc,
Z3 4.13. Raw per-instance rows are in `results/*.tsv`; `python3 summarise.py` prints these statistics.

"Single" means one target per SAT call. "Batched" means one call whose target set is the whole miss set
of a pool, merged into intervals, so one UNSAT proves every miss of that pool.

## Agreement

**There is no disagreement anywhere.** Every instance the study lists as a miss came out UNSAT with a
proof that cake_lpr verified (and, for pilot 1, that lrat-check also verified), or was proved in Lean;
every instance the study lists as solvable came out SAT, and its decoded expression was accepted by the
independent evaluator in `encode.py`.

| check | result |
|---|---|
| standalone UNSAT proofs checked by cake_lpr | 3,618 of 3,618 verified (pilot 1: 654, pilot 2: 2,058, pilot 3: 576, batches: 138 + 92 + 100) |
| pilot 1 proofs also checked by lrat-check | 654 of 654 verified |
| SAT instances decoded and evaluated | 592 of 592 accepted (247 worst pool, 325 cats pool, 20 barely solvable) |
| Lean theorem files compiled | 1,016 proved (single: 653 + 100 + 100; batched: 1 + 2 + 100 + 30 + 30) plus `Examples.lean`, 0 errors after one generator fix (below) |
| Lean axiom audit | every theorem: `propext, Classical.choice, Quot.sound` plus exactly its own `…_native.bv_decide.ax_…` |
| CaDiCaL models fed back into the Lean `Enc` by `#eval` | 591 of 591 give `true`, and `false` once the target set is moved; the 592nd is target 100 on `1 1 25 50 75 100`, a pool number, where the CNF is trivially true and `Enc` leaves the case to `hleaf`, so `false` is expected |
| Z3 on the SMT-LIB rendering | 20 of 20 agree (16 worst pool, 4 cats pool, both SAT and UNSAT) |
| corrupted LRAT hint | rejected by both cake_lpr and lrat-check |

Two runner problems were found and fixed; neither is a disagreement. (1) A target equal to a pool number
(cats target 100) was first marked "NO" because the decoder returns no expression; `summarise.py` and the
runner now accept it. (2) Eight batched Lean files with long target lists hit `maxRecDepth` in the wrapper
theorem; the axiom audit caught the resulting `sorryAx`, and all eight were proved after adding
`set_option maxRecDepth` to the generator.

## Pilot 1: worst standard pool `1 1 2 2 3 25` (width 12), all 900 targets

| | n | solve s mean / median / max | peak MB | proof MB mean / max | cake_lpr s mean (peak MB) | lrat-check s mean |
|---|---:|---|---:|---|---|---:|
| misses, single, UNSAT | 653 | 0.93 / 0.89 / 2.78 | 15 | 14.4 / 25.0 | 0.86 (510; 1,024 MB heap from pilot 2 on) | 0.25 |
| solvable, single, SAT | 247 | 0.64 / 0.66 / 1.74 | 15 | | | |
| all 653 misses, batched | 1 | 2.32 | 22 | 39.7 | 2.04 | 0.59 |

CNF: 11,262 variables, about 33,170 clauses; encoding takes 0.04 s.

Lean: all 653 misses proved singly, mean 3.04 s, median 2.95 s, max 5.60 s, about 730 MB each; all 653
in one theorem in 8.6 s and 1.27 GB. Lean start-up with `import CountdownSat` is 0.26 s.

## Pilot 2: target 967 against all 2,058 standard pools that miss it (widths 12 to 26)

| | n | solve s mean / median / p95 / max | peak MB | proof MB mean / max | cake_lpr s mean / max |
|---|---:|---|---:|---|---|
| standalone, UNSAT | 2,058 | 4.42 / 3.84 / 9.28 / 17.1 | 25 (max 40) | 31 / 119 | 2.15 / 7.46 |
| Lean, random sample | 100 | 9.19 / 8.01 / 18.1 / 22.6 (whole file) | 966 (max 1,508) | | |

All 2,058 standalone proofs verified; mean total per instance including encoding and checking 7.3 s.

## Pilot 3: cats pool `1 1 25 50 75 100` (width 26), all 900 targets

| | n | solve s mean / median / max | peak MB | proof MB mean / max | cake_lpr s mean / max |
|---|---:|---|---:|---|---|
| misses, single, UNSAT | 575 | 18.97 / 18.40 / 34.3 | 41 | 106 / 160 | 7.0 / 11.2 |
| solvable, single, SAT | 325 | 5.76 / 4.74 / 24.9 | 39 | | |
| all 575 misses, batched | 1 | 39.1 | 74 | 312 | 14.8 |

CNF: about 41,400 variables and 123,170 clauses. Lean: a random 100 of the 575 misses singly, mean 25.4 s
(max 44.9 s, 1.3 GB); all 575 in one theorem in 61 to 63 s and 2.2 GB. Wide values cost about 20 times
the narrow worst pool per single instance, but the batched call is only 17 times dearer.

## Pilot 4: barely solvable instances

20 targets that need all six numbers (from a fixed random sample of pools, widths 16 to 23): all SAT, mean
2.36 s, max 4.9 s, and every decoded expression uses all six numbers, for example
`((((6 * 10) * (5 + 25)) - 2) / 2) = 899` from `2 2 5 6 10 25` and `(75 / 25) + (10 * (1 + (5 * 10))) = 513`.
Finding a solution is several times faster than refuting one of similar width.

## Pilot 5: batched samples for extrapolation

One call per pool proving its whole miss set (stopped at 12:40 by the time box; the six processes in
flight then had run for at most 20 s, so nothing timed out and nothing was left unfinished for long).

| mode | pools with misses | standalone sample | total s per pool mean / max (solve+check) | proof MB mean / max | Lean sample | Lean s per pool mean / max (peak MB max) |
|---|---:|---:|---|---|---:|---|
| standard | 8,281 | 138 | 24.3 / 128.7 | 117 / 536 | 100 | 25.3 / 109.0 (2,976) |
| cats (ℓ = 0, 3, 4) | 3,736 | 92 | 32.3 / 196.5 | 178 / 963 | 30 | 29.0 / 97.2 (3,052) |
| nasty | 8,596 | 100 | 15.4 / 44.2 | 85 / 269 | 30 | 18.1 / 52.9 (2,186) |

The slowest cats batches are the 4-large pools (width up to 31): 137 s to solve and 59 s to check, with
proofs up to 963 MB. CaDiCaL never needed more than 112 MB; cake_lpr is capped at a 1,024 MB heap and
never needed the 5,000 MB retry; Lean needed at most 3.1 GB.

## Extrapolation to a full run

Batched (one call per pool), from the sample means above, in single-core hours:

| mode | missed instances | pools | standalone (solve + cake_lpr) | Lean `bv_decide` |
|---|---:|---:|---:|---:|
| standard | 380,523 | 8,281 | 56 h | 58 h |
| cats | 666,191 | 3,736 | 34 h | 30 h |
| nasty | 382,225 | 8,596 | 37 h | 43 h |
| all | 1,428,939 | 20,613 | 127 h | 131 h |

On the eight CPUs used here (24 to 31) the standard set takes about 7 hours per route and all three modes
about 16 hours per route. On all 32 hardware threads (cake_lpr needs 1 GB, Lean at most 3.1 GB, so 30 GB
allows about 9 Lean or 25 standalone workers) the standard set takes about 3 hours standalone and 6 to 7
hours in Lean. **A full run is realistic on this machine**, in a day per route for all modes. Proofs
should be deleted after checking as here: the standard set alone generates about 1 TB of LRAT (117 MB
per pool), more than the 422 GB free, but no proof needs to live longer than its check.

Single-target calls would cost far more: 7.3 s per standard instance standalone (pilot 2) and 9.2 s in
Lean give about 770 and 970 single-core hours for the 380,523 standard misses, about 14 times the
batched cost, and about 5 days on eight cores.

## Encoding variants measured

On `9 9 10 10 50 100` target 967 (width 26) and `1 1 2 2 3 25` target 179 (width 12), CaDiCaL without proof:

| variant | 967 | 179 |
|---|---:|---:|
| first version, separate adder per op, two multipliers | 11.9 s | 1.3 s |
| one shared adder and one shared multiplier (opi swaps xa and r) | 6.8 s | 0.93 s |
| without C7, C8 and C10 | 13.5 s | 1.54 s |
| plus C7 and C8 (post-order use) | 6.8 s | 1.14 s |
| plus C10 (no result equal to an operand, no early target) | **5.4 s** | **0.95 s** |
| plus "position j used implies equal-valued position i < j used" | 6.8 s | 1.14 s (tried without C10; no gain, rejected) |
| CaDiCaL `--unsat` / `--sat` / `--elim=0` | 6.6 / 9.8 / 33 s | |
| batched miss set instead of one target | whole pool in 2.3 s | |

## Cost of this pilot

Claude Opus 5.5 in Claude Code, about 3.5 hours of wall time (09:20 to 12:50) and on the order of 300k
tokens. Measured: 4,210 standalone instances (901 + 2,058 + 901 + 20 + 330 batches), 20 Z3 runs, 1,016
Lean theorem files and 592 model evaluations in Lean; 7 encoding variants timed.
