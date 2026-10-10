# Countdown solvability in Lean 4

A Lean 4 formalisation of how often a Countdown numbers round has no exact solution: a decision procedure
for exact solvability with kernel-checked soundness and completeness, and the exhaustive counts over every
pool. It uses Lean 4.34.1 core only, with no Mathlib and no Batteries.

## Why no Mathlib

Core Lean 4.34 already has everything needed: `List.Nodup`, `List.Perm`, bitwise `Nat.testBit` lemmas,
`Rat` with its arithmetic lemmas, `grind` for the field algebra, and `decide +kernel`. Mathlib would add a
multi-gigabyte dependency and longer builds without shortening any proof here. With no dependencies the
project builds offline in about a minute and a half and the trusted base is as small as it can be.

## Files

| File | Contents |
|---|---|
| `Countdown/Expr.lean` | `Op`, `Expr`, `Expr.eval`, `Expr.Legal`, `Solvable`, invariance under permuting the pool |
| `Countdown/Solver.lean` | the decision procedure (`table`, `reachable`, `solvableB`) and its correctness proofs |
| `Countdown/Bound.lean` | the value bound of Proposition `prop:bound` |
| `Countdown/Pools.lean` | the deck, deals, pools, weights, miss counts and the deal-level probability, all parametrised by the large set and by ℓ |
| `Countdown/Count.lean` | the four `native_decide` facts and the main theorems |
| `Countdown/Kernel.lean` | kernel-only checks of the worst pool with the same functions |
| `Axioms.lean` | `#print axioms` for the main theorems |
| `Export.lean` | an executable that writes the per-pool missed targets to `out/` for cross-checking (not part of the proof) |

## Definitions (faithfulness)

```lean
def Op.apply : Op → Nat → Nat → Option Nat
  | .add, a, b => some (a + b)
  | .sub, a, b => if b < a then some (a - b) else none
  | .mul, a, b => some (a * b)
  | .div, a, b => if 0 < b ∧ b ∣ a then some (a / b) else none

inductive Expr where
  | leaf (i : Nat)                 -- Index a pool position rather than a value
  | node (op : Op) (l r : Expr)

def Expr.eval (p : List Nat) : Expr → Option Nat   -- Return none unless every value including each leaf is positive
def Expr.leaves : Expr → List Nat                 -- List the positions used from left to right
def Expr.Legal (e : Expr) : Prop := e.leaves.Nodup
def Solvable (p : List Nat) (t : Nat) : Prop := ∃ e : Expr, e.Legal ∧ e.eval p = some t
```

* Leaves are pool positions and `Legal` requires them to be distinct, so each dealt card is used at most
  once even when two cards have equal values. Not every position has to be used.
* These are the game's looser rules: operands may come in either order, and `× 1` and `÷ 1` are allowed.
  Every intermediate value must be a positive integer, so subtraction must be positive and division exact.
  For exact solvability with `t ≥ 1` this is equivalent to the paper's restricted rules
  (Proposition `prop:restriction`). The exhaustive study used the restricted rules, and every per-pool miss
  set agrees exactly.
* `solvable_perm : p.Perm q → (Solvable p t ↔ Solvable q t)`, so solvability depends only on the multiset
  of numbers. Pools can therefore be represented as sorted lists.

The deal model (`Pools.lean`): with ℓ large numbers, a deal is a pair of a `(6 − ℓ)`-element subset of the
20-card small deck `[1,1,2,2,…,10,10]` and an ℓ-element subset of the large set, all pairs equally likely
(`deals large ℓ`, listing the small cards then the large ones, as in the paper). `pools large ℓ` mirrors
`countdown-table/pools.py`. `missProb large ℓ` is the probability, over a uniform deal and a uniform target
in 100..999, that `¬ Solvable`. `gameMissProb` is the average of `missProb standardLarge 1` and
`missProb standardLarge 2`. The pool weight is
`weight large ℓ P = ∏ C(2, cᵢ) / C(20, 6 − ℓ) / C(|large|, ℓ)`, and a game pool has weight ½ times that.

## Main theorems

Decision procedure (`Solver.lean`, kernel-checked, no `native_decide`):

```lean
theorem mem_table (p : List Nat) {m : Nat} (hm : 0 < m) (hmn : m < 2 ^ p.length) (v : Nat) :
    v ∈ (table p).getD m [] ↔ ∃ e : Expr, e.Legal ∧ e.mask = m ∧ e.eval p = some v
theorem mem_reachable (p : List Nat) (t : Nat) : t ∈ reachable p ↔ Solvable p t
theorem solvableB_iff (p : List Nat) (t : Nat) : solvableB p t = true ↔ Solvable p t
instance (p : List Nat) (t : Nat) : Decidable (Solvable p t)
```

The `→` direction of `mem_table` is soundness (each computed value has a legal expression with exactly that
leaf mask). The `←` direction is completeness. `table p` combines every unordered split of each mask
into two disjoint non-empty submasks (Theorem `thm:recursion`). Values are never truncated, and there is no
value bound, so 4-large pools (values up to 937,500,000) are handled the same way. Sets are lists kept
sorted by merging, but the proofs use only membership.

Value bound (`Bound.lean`, kernel-checked):

```lean
theorem eval_add_one_le_prod {p : List Nat} {e : Expr} {v : Nat} (h : e.eval p = some v) :
    v + 1 ≤ (e.leaves.map fun i => p.getD i 0 + 1).prod
```

Pool enumeration (`Count.lean`, kernel-checked by `decide +kernel`):

```lean
theorem boundedMultisets_count :
    ((List.range 7).map fun k => (boundedMultisets smallValues k).length) = (trinomialCoeffs 10).take 7 ∧
      (trinomialCoeffs 10).take 7 = [1, 10, 55, 210, 615, 1452, 2850]
theorem pools_count :
    ((List.range 5).map fun ℓ => (pools standardLarge ℓ).length) = [2850, 5808, 3690, 840, 55] ∧
      ((List.range 5).map fun ℓ => (pools nastyLarge ℓ).length) = [2850, 5808, 3690, 840, 55] ∧
      gamePools.length = 9498 ∧ 6 * 615 + 4 * 1452 = 9498
theorem instances_count : (gamePools.flatMap fun p => targets.map fun t => (p, t)).length = 8548200
```

The counts and the probability (`Count.lean`, which relies on `native_decide`):

```lean
theorem unsolvable_count : (unsolvablePairs gamePools).length = 380523
theorem gameMissProb_eq : gameMissProb = 16970693 / 837216000
theorem gameMissProb_eq_weighted : gameMissProb =
    ((pools standardLarge 1).map fun P => (1 / 2) * weight standardLarge 1 P * ((missCount P : Rat) / 900)).sum +
    ((pools standardLarge 2).map fun P => (1 / 2) * weight standardLarge 2 P * ((missCount P : Rat) / 900)).sum
theorem gameWeights_sum_eq_one :
    ((pools standardLarge 1).map fun P => (1 / 2) * weight standardLarge 1 P).sum +
    ((pools standardLarge 2).map fun P => (1 / 2) * weight standardLarge 2 P).sum = 1
theorem unsolvable_count_by_large :
    ((List.range 5).map fun ℓ => (unsolvablePairs (pools standardLarge ℓ)).length) =
      [598427, 255316, 125207, 62029, 5735] ∧
    ((List.range 5).map fun ℓ => (unsolvablePairs (pools nastyLarge ℓ)).length) =
      [598427, 314793, 60172, 6759, 501]
theorem missProb_standard :
    ((List.range 5).map (missProb standardLarge)) =
      [2811013 / 17442000, 627787 / 27907200, 236059 / 13081500, 54029 / 1026000, 16307 / 171000]
theorem missProb_nasty :
    ((List.range 5).map (missProb nastyLarge)) =
      [2811013 / 17442000, 293059 / 9302400, 8167 / 1046520, 2819 / 684000, 17 / 3800]
```

Here `unsolvablePairs ps` is the list of `(p, t)` with `p ∈ ps`, `t ∈ 100..999` and `¬ Solvable p t`.
`16970693 / 837216000 ≈ 0.020270387809`.

Kernel-only slice (`Kernel.lean`, `decide +kernel` on the same `missCount`/`reachable` code):

```lean
theorem worst_pool_missCount : missCount [1, 1, 2, 2, 3, 25] = 653
theorem worst_pool_unsolvable : (targets.filter fun t => ¬ Solvable [1, 1, 2, 2, 3, 25] t).length = 653
theorem worst_pool_above {t : Nat} (ht : 675 < t) : ¬ Solvable [1, 1, 2, 2, 3, 25] t
theorem worst_pool_179 : ¬ Solvable [1, 1, 2, 2, 3, 25] 179 ∧ ∀ t ∈ List.range' 100 79, Solvable [1, 1, 2, 2, 3, 25] t
```

## What is trusted

* **Kernel only** (axioms `propext`, `Classical.choice`, `Quot.sound` at most): the semantics, soundness and
  completeness of the decision procedure, permutation invariance, the value bound, the pool counts, the
  probability algebra (`missProb_eq_weighted`, `weights_sum_eq_one`, the regrouping of deals into pools) and
  the whole worst-pool slice. `worst_pool_missCount` needs only `propext`.
* **`native_decide` (Lean compiler plus compiled code)**: exactly four facts in `Count.lean`.
  * `dealsMatch_standard` and `dealsMatch_nasty`: for ℓ = 0..4, the pools are distinct, every deal is a pool,
    each pool arises from exactly `∏ C(2, cᵢ)` deals, and there are `C(20, 6 − ℓ) · C(4, ℓ)` deals.
  * `stats_standard` and `stats_nasty`: for ℓ = 0..4, the sum of `missCount` over the pools and the sum of
    `∏ C(2, cᵢ) · missCount`.

  `#print axioms` lists these as `…_native.native_decide.ax_1_1`. Every theorem in the list above that
  states a count or probability depends on them, and on nothing else beyond the standard axioms.
  `missCount` is proved equal to the number of `t ∈ 100..999` with `¬ Solvable p t` (`missCount_eq`), and
  the parallel `parMap`/`parSum` helpers are proved equal to plain `map`/`sum`. The compiled evaluation
  therefore runs exactly the verified functions, using `Task.spawn` for parallelism.

## Cross-checks

`lake exe export` writes `out/misses_{standard,nasty}_{0..4}.tsv`. Every row of
`../data/misses.tsv` (9,498 pools), `../data/misses_cats.tsv` (3,745 pools) and `../data/misses_nasty.tsv`
(10,393 pools) matches, including the exact list of missed targets. The probabilities match `../RESULTS.md`.

## Rebuilding

```sh
export PATH=$HOME/.elan/bin:$PATH
systemd-run --user --scope -q -p MemoryMax=8G -p MemorySwapMax=0 timeout 3600 taskset -c 24-31 lake build
lake env lean Axioms.lean        # print the axioms of the main theorems
lake build export && .lake/build/bin/export   # optional: write out/*.tsv
```

On CPUs 24-31 a clean `lake build` takes about 95 s wall (360 s CPU) with a peak of about 6 GB. Of that,
`Countdown.Count` takes 90 s (the four `native_decide` runs over 23,636 pools, in parallel) and
`Countdown.Kernel` takes 73 s (the kernel evaluating the worst pool). The two run concurrently, and the
other modules take a few seconds. `precompileModules = true` makes `native_decide` call native code rather
than the interpreter.
