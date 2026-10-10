# SAT cross-check of Countdown unsolvability

This directory proves, with a SAT solver, that selected Countdown rounds have **no exact solution**. It is
an independent cross-check of the exhaustive search (`../checker`, `countdown-c`, `answers.bin`) and of the
Lean decision procedure in `../lean`. It reuses the Lean definitions `Expr`, `Expr.eval`, `Expr.Legal` and
`Solvable` from `../lean/Countdown/Expr.lean` unchanged.

Two trust routes are provided:

* **(a) Lean + `bv_decide`.** For each instance a theorem `¬ Solvable p t` (or `∀ t ∈ M, ¬ Solvable p t`
  for a whole miss set `M`) is proved from the kernel-checked completeness theorem
  `Countdown.Sat.not_solvable_of_unsat` and one `bv_decide` call.
* **(b) Standalone CaDiCaL + verified checker.** `encode.py` writes DIMACS CNF with its own bit-blaster,
  CaDiCaL 2.1.3 writes an LRAT proof, and `cake_lpr` (the CakeML-verified LRAT/LPR checker) checks every
  proof. For one pilot set `lrat-check` from drat-trim checks every proof as well.

Pilot results, timings, proof sizes and the extrapolation are in [RESULTS.md](RESULTS.md).

## Layout

| Path | Contents |
|---|---|
| `encode.py` | the encoding, written once against a builder interface with two back ends: an and-inverter-graph bit-blaster that writes DIMACS, and an SMT-LIB printer for Z3; also the model decoder and a small independent expression evaluator |
| `run_cnf.py` | route (b): encode, solve with `cadical --lrat`, check with `cake_lpr` (and optionally `lrat-check`), decode and evaluate every model |
| `run_lean.py` | route (a): write one Lean file per instance, compile it under a memory cap and audit `#print axioms` |
| `make_jobs.py` | build the pilot job lists in `jobs/` from `../data/misses*.tsv` |
| `model_check.py` | feed every CaDiCaL model of the Python CNF back into the Lean definition `Enc` with `#eval` |
| `z3_check.py` | solve a sample through the SMT-LIB rendering with Z3 to cross-check the bit-blaster |
| `summarise.py` | print the statistics quoted in RESULTS.md |
| `results/` | one TSV row per instance (time, peak memory, proof size, checker verdicts, decoded expression) |
| `lean/` | a separate Lake project that requires `../../lean` by path, so the existing build is untouched |
| `lean/CountdownSat/Enc.lean` | the bit-vector encoding `Enc` and the `enc_unsat` tactic |
| `lean/CountdownSat/Normal.lean` | normalising a solution (pruning and first hit) |
| `lean/CountdownSat/Compile.lean` | compiling an expression to a post-order straight-line program and its invariants |
| `lean/CountdownSat/Complete.lean` | completeness of the encoding: `enc_complete` and `not_solvable_of_unsat` |
| `lean/Examples.lean` | sample instance theorems and `#print axioms` |
| `tools/` | checkers built from source (see "Checkers" below) |

## The encoding

A solution is encoded as a straight-line program of at most five steps (six cards give at most five
operations). Registers 0 to 5 hold the pool numbers and register `6 + k` holds the result of step `k`.
Per step `k` the free variables are

* `act` (Bool): the step is in use,
* `sa`, `sb` (4-bit): the operand registers,
* `opm`, `opi` (Bool): the operation, `(opm, opi)` = add, sub, mul, div for `(0,0)`, `(0,1)`, `(1,0)`, `(1,1)`,
* `xa`, `xb`, `r` (w-bit): the operand values and the result.

The target is a set of closed intervals `ivs` (a single target is `[(t, t)]`; a whole miss set of a pool
is merged into intervals, so one call proves every miss of the pool). The constraints, identical in
`encode.py` and in `Enc` (`lean/CountdownSat/Enc.lean`), are

| | constraint | why it is allowed |
|---|---|---|
| C1 | active steps form a prefix and step 0 is active | post-order numbering |
| C2 | `sa, sb < 6 + k` | operands come from earlier registers |
| C3 | `sa = j → xa = reg j`, same for `sb`, for every `j < 6 + k` | operand values |
| C4 | `r ≠ 0`; add as `xb + xa = r`, sub as `xb + r = xa` in `w+1` bits; mul as `xb · xa = r`, div as `xb · r = xa` in `2w` bits, all zero-extended | exact arithmetic with no wrap-around; division is multiplication, so the quotient is exact and the divisor positive |
| C5 | all operand slots of active steps select distinct registers | each card and each intermediate result is used at most once |
| C6 | the last active result lies in `ivs` | the target |
| C7 | every active result except the last is an operand of a later step | post-order |
| C8 | if a step reads a step result, one operand is the previous step's result | post-order |
| C9 | for add and mul, `sa < sb` | commutativity |
| C10 | `r ≠ xa`, `r ≠ xb`, and no result before the last lies in `ivs` | a solution with the fewest nodes never has a node equal to a child in value, and never contains a proper subexpression already in `ivs` |

The add and sub cases share one adder and the mul and div cases share one multiplier: `opi` swaps the
roles of `xa` and `r`. C7, C8, C9 and C10 only break symmetry; dropping C7, C8 and C10 makes CaDiCaL
2 to 2.5 times slower on the instances tried (RESULTS.md, "Encoding variants").

**Width.** `w` is the least width with `∏(pᵢ + 1) ≤ 2^w` and every target below `2^w`. By
`eval_add_one_le_prod` (`../lean/Countdown/Bound.lean`) every value of a legal expression is below
`∏(pᵢ + 1)` over its leaves, so every value of a genuine solution fits in `w` bits, and the zero-extended
sums and products cannot wrap. Widths are 12 for `1 1 2 2 3 25`, 26 for `1 1 25 50 75 100` and at most
27 for standard pools (31 for cats pools with all four large numbers).

## Faithfulness (Lean, kernel-checked, no `sorry`, no native code)

```lean
theorem Countdown.Sat.enc_complete {p : List Nat} {ivs : List (Nat × Nat)} {w : Nat}
    (hlen : p.length = 6)
    (hw : ((List.range 6).map fun i => p.getD i 0 + 1).prod ≤ 2 ^ w)
    (hiv : ∀ iv ∈ ivs, iv.1 < 2 ^ w ∧ iv.2 < 2 ^ w)
    (hleaf : ∀ v ∈ p, inNat ivs v = false)
    {t : Nat} (ht : inNat ivs t = true) (hsol : Solvable p t) :
    ∃ s0 s1 s2 s3 s4 : Step w, Enc p ivs w (pick [s0, s1, s2, s3, s4]) = true

theorem Countdown.Sat.not_solvable_of_unsat ... (same hypotheses)
    (hunsat : ∀ s0 s1 s2 s3 s4 : Step w, Enc p ivs w (pick [s0, s1, s2, s3, s4]) = false)
    {t : Nat} (ht : inNat ivs t = true) : ¬ Solvable p t
```

`#print axioms` for both: `[propext, Classical.choice, Quot.sound]`. The four side conditions are closed
by `decide` per instance. `hleaf` excludes targets that are themselves pool numbers (none are misses).

Proof outline:

1. `prune_spec` (`Normal.lean`): replacing every node whose value equals a child's value by that child
   keeps the value, keeps a sublist of the leaves (so legality) and makes the expression `Tight`.
2. `find_some`, `find_isSome`: the first subexpression in post-order whose value lies in `ivs` exists, is
   tight and legal, and its children are `Clean` (no subexpression of them lies in `ivs`). If it is a leaf,
   `hleaf` is contradicted.
3. `compile` (`Compile.lean`) turns the node into a post-order list of steps, numbering registers from 6.
   `compile_perm`: the operand registers plus the root are a permutation of the leaves plus the new
   registers, which gives C5 (distinctness), C7 (use) and at most five steps. `compile_inv`: every
   operand register holds the right value and comes earlier (C2, C3), C8 holds, the arithmetic of each
   step holds in the form of C4 and C9, results differ from operands (C10) and every value is bounded by
   `∏(pᵢ + 1)` over the leaves. `compile_clean`: no step before the last lies in `ivs` (C10).
4. `enc_asg` (`Complete.lean`) turns those natural-number facts into the bit-vector constraints of `Enc`
   using `prod_le_range` (the leaves' product is at most the pool's) and the in-range `BitVec.ofNat`
   lemmas.

The encoding is not proved sound (a model might not be a legal expression), and need not be: only
UNSAT answers are used as proofs. Every SAT answer in the pilots is nevertheless decoded and accepted by
an independent evaluator.

## Trust bases

**Route (a), Lean.** Each instance theorem prints

    'miss_…' depends on axioms: [propext, Classical.choice, Quot.sound, enc_…._native.bv_decide.ax_1_N]

In Lean 4.34 `bv_decide` does not use `Lean.ofReduceBool` directly. It reflects the goal into a
`BVLogicalExpr`, runs CaDiCaL 2.1.2 (bundled with the toolchain) to get an LRAT certificate, then calls
`Lean.Meta.nativeEqTrue`, which compiles and runs `Std.Tactic.BVDecide.Reflect.verifyBVExpr expr cert`
and, if it returns `true`, adds the auxiliary axiom `verifyBVExpr expr cert = true` (shown above as
`…_native.bv_decide.ax_1_N`). `verifyBVExpr` (bit-blaster to AIG, Tseitin, LRAT checker) is proved sound
in Lean, so the trusted base is the Lean kernel plus the Lean compiler and runtime that evaluated that
one closed Boolean term; this is the same trust as `Lean.ofReduceBool`/`Lean.trustCompiler`, scoped to
one named axiom per theorem. CaDiCaL itself is not trusted. The completeness theorem and the `decide`
side conditions are checked by the kernel alone.

**Route (b), standalone.** Trusted: `encode.py` (my own bit-blaster, about 250 lines, not verified), the
completeness argument (proved in Lean for the identical constraint list, see above), and `cake_lpr`.
`cake_lpr` is verified in HOL4 down to x64 machine code by the CakeML compiler; its trusted base is the
HOL4 kernel, the CakeML/ISA models and the small C file `basis_ffi.c` used for I/O. CaDiCaL is not
trusted. The bit-blaster is cross-validated three ways (see RESULTS.md): every UNSAT agrees with the
exhaustive search, every SAT model decodes to an expression the evaluator accepts, every pilot SAT model
also satisfies the Lean definition `Enc` when evaluated in Lean (`model_check.py`), and Z3 on the SMT-LIB
rendering agrees on a sample (`z3_check.py`).

## Checkers

* `tools/cake_lpr`: <https://github.com/tanyongkiam/cake_lpr> at a36874a (22 Jul 2026), built with
  `make` from the shipped `cake_lpr.S` produced by the verified CakeML compiler (HOL4 0ae7030, CakeML
  fb377b4). It accepts binary LRAT and needs `--CML_HEAP_SIZE` (MB); the runner uses 1024 and retries
  with 5000. Note that it exits with status 0 even when a proof fails, so the runner checks for
  `s VERIFIED UNSAT` on standard output. A deliberately corrupted hint is rejected.
* `tools/drat-trim/lrat-check`: <https://github.com/marijnheule/drat-trim> at 2e3b2dc, built with
  `gcc -O2`. Unverified C, used as a second opinion on ASCII LRAT; it prints `c VERIFIED`.

Rebuild: `make -C tools/cake_lpr` and `gcc -O2 -o tools/drat-trim/lrat-check tools/drat-trim/lrat-check.c`.

## Running

Every external process runs under `systemd-run --user --scope -p MemoryMax=… -p MemorySwapMax=0`,
`timeout` and `taskset` (see `capped` in `run_cnf.py`).

```sh
python3 make_jobs.py
python3 run_cnf.py jobs/p1_worst.tsv results/p1_worst.tsv --workers 4 --cpus 24-27 --lrat-check
python3 run_lean.py jobs/p1_worst.tsv results/lean_p1_worst.tsv --workers 2 --cpus 28-29
python3 summarise.py
(cd lean && lake build && lake env lean Examples.lean)
```

Both runners resume from an existing output file. Proof files are deleted as soon as they are checked;
their sizes are recorded.
