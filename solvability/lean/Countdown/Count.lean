import Countdown.Pools

/-! Derive the counts and probabilities, trusting compiled code only in the four `native_decide` theorems -/

namespace Countdown

/-! Do the rational bookkeeping -/

theorem sum_natCast_mul {α : Type} (l : List α) (f : α → Nat) (c : Rat) :
    (l.map fun x => (f x : Rat) * c).sum = ((l.map f).sum : Rat) * c := by
  induction l with
  | nil => simp
  | cons x l ih => simp only [List.map_cons, List.sum_cons, ih, Rat.natCast_add, Rat.add_mul]

theorem binom_pos : ∀ {n k : Nat}, k ≤ n → 0 < binom n k
  | _, 0, _ => by simp [binom]
  | 0, _ + 1, h => by omega
  | n + 1, k + 1, h => by
    have := binom_pos (n := n) (k := k) (by omega)
    simp only [binom]; omega

theorem sum_mul_left {α : Type} (l : List α) (f : α → Rat) (c : Rat) :
    (l.map fun x => c * f x).sum = c * (l.map f).sum := by
  induction l with
  | nil => simp
  | cons x l ih => simp only [List.map_cons, List.sum_cons, ih, Rat.mul_add]

/-- Rewrite the deal-level probability as the sum of pool weights times missed fractions -/
theorem missProb_eq_weighted {large : List Nat} {ℓ : Nat} (h : dealsMatchPools large ℓ = true)
    (hℓ : ℓ ≤ large.length) :
    missProb large ℓ =
      ((pools large ℓ).map fun P => weight large ℓ P * ((missCount P : Rat) / 900)).sum := by
  have h1 : (binom 20 (6 - ℓ) : Rat) ≠ 0 := by
    have := binom_pos (n := 20) (k := 6 - ℓ) (by omega)
    simp only [ne_eq, Rat.natCast_eq_zero_iff]; omega
  have h2 : (binom large.length ℓ : Rat) ≠ 0 := by
    have := binom_pos hℓ
    simp only [ne_eq, Rat.natCast_eq_zero_iff]; omega
  rw [missProb_eq h, stats_eq]
  have hterm : ∀ P, weight large ℓ P * ((missCount P : Rat) / 900) =
      ((smallWays P * missCount P : Nat) : Rat) *
        (1 / ((binom 20 (6 - ℓ) * binom large.length ℓ * 900 : Nat) : Rat)) := by
    intro P
    simp only [weight, Rat.natCast_mul]
    grind
  rw [List.map_congr_left (fun P _ => hterm P), sum_natCast_mul]
  grind

/-- Show that the weights of the pools with `ℓ` large numbers sum to one -/
theorem weights_sum_eq_one {large : List Nat} {ℓ : Nat} (h : dealsMatchPools large ℓ = true)
    (hℓ : ℓ ≤ large.length) : ((pools large ℓ).map (weight large ℓ)).sum = 1 := by
  have h1 : (binom 20 (6 - ℓ) : Rat) ≠ 0 := by
    have := binom_pos (n := 20) (k := 6 - ℓ) (by omega)
    simp only [ne_eq, Rat.natCast_eq_zero_iff]; omega
  have h2 : (binom large.length ℓ : Rat) ≠ 0 := by
    have := binom_pos hℓ
    simp only [ne_eq, Rat.natCast_eq_zero_iff]; omega
  -- Count the deals two ways
  have hcount := sum_deals_eq h (fun _ => 1)
  simp only [Nat.mul_one] at hcount
  have hlen : ((deals large ℓ).map fun _ => 1).sum = (deals large ℓ).length := by
    clear hcount; induction (deals large ℓ) with
    | nil => rfl
    | cons d ds ih => simp [ih]; omega
  rw [hlen, (dealsMatchPools_spec h).2.2.2] at hcount
  have hterm : ∀ P, weight large ℓ P =
      (smallWays P : Rat) * (1 / ((binom 20 (6 - ℓ) * binom large.length ℓ : Nat) : Rat)) := by
    intro P
    simp only [weight, Rat.natCast_mul]
    grind
  rw [List.map_congr_left (fun P _ => hterm P), sum_natCast_mul, ← hcount, Rat.natCast_mul]
  grind

/-! Count the pools as in Proposition `prop:pools` -/

/-- List the coefficients of `(1 + x + x²) ^ n` -/
def trinomialCoeffs : Nat → List Nat
  | 0 => [1]
  | n + 1 =>
    let c := trinomialCoeffs n
    (List.range (c.length + 2)).map fun k => c.getD k 0 + c.getD (k - 1) 0 * (if k ≥ 1 then 1 else 0) +
      c.getD (k - 2) 0 * (if k ≥ 2 then 1 else 0)

/-- List the values 1 to 10 -/
def smallValues : List Nat := (List.range 10).map (· + 1)

theorem length_pools (large : List Nat) (ℓ : Nat) :
    (pools large ℓ).length = (choose ℓ large).length * (boundedMultisets smallValues (6 - ℓ)).length := by
  unfold pools smallValues
  generalize choose ℓ large = Ls
  induction Ls with
  | nil => simp
  | cons L Ls ih => simp [ih, Nat.add_mul, Nat.add_comm]

/-- Check the small-number multisets against the coefficients of `(1 + x + x²) ^ 10` -/
theorem boundedMultisets_count :
    ((List.range 7).map fun k => (boundedMultisets smallValues k).length) = (trinomialCoeffs 10).take 7 ∧
      (trinomialCoeffs 10).take 7 = [1, 10, 55, 210, 615, 1452, 2850] := by
  decide +kernel

/-- Count the pools for each number of large numbers, so that the standard game has `6 · 615 + 4 · 1452 = 9498` -/
theorem pools_count :
    ((List.range 5).map fun ℓ => (pools standardLarge ℓ).length) = [2850, 5808, 3690, 840, 55] ∧
      ((List.range 5).map fun ℓ => (pools nastyLarge ℓ).length) = [2850, 5808, 3690, 840, 55] ∧
      gamePools.length = 9498 ∧ 6 * 615 + 4 * 1452 = 9498 := by
  simp only [gamePools, List.length_append, length_pools]
  decide +kernel

/-- Count the instances of the standard game -/
theorem instances_count : (gamePools.flatMap fun p => targets.map fun t => (p, t)).length = 8548200 := by
  rw [List.length_flatMap]
  simp only [List.length_map, targets_length]
  have hrep : ∀ n, (List.replicate n 900).sum = n * 900 := by
    intro n; induction n with
    | zero => rfl
    | succ n ih => rw [List.replicate_succ, List.sum_cons, ih]; omega
  rw [List.map_const', hrep, pools_count.2.2.1]

/-! Check the remaining facts by compiled evaluation with `native_decide` -/

/-- Check the deal bookkeeping for the standard large numbers by compiled evaluation -/
theorem dealsMatch_standard : [0, 1, 2, 3, 4].all (dealsMatchPools standardLarge) = true := by
  native_decide

/-- Check the deal bookkeeping for the nasty large numbers by compiled evaluation -/
theorem dealsMatch_nasty : [0, 1, 2, 3, 4].all (dealsMatchPools nastyLarge) = true := by
  native_decide

/-- Evaluate the miss totals for the standard large numbers by compiled evaluation -/
theorem stats_standard : [0, 1, 2, 3, 4].map (stats standardLarge) =
    [(598427, 5622026), (255316, 1255574), (125207, 472118), (62029, 216116), (5735, 16307)] := by
  native_decide

/-- Evaluate the miss totals for the nasty large numbers by compiled evaluation -/
theorem stats_nasty : [0, 1, 2, 3, 4].map (stats nastyLarge) =
    [(598427, 5622026), (314793, 1758354), (60172, 204175), (6759, 16914), (501, 765)] := by
  native_decide

theorem dealsMatch_of_all {large : List Nat} (h : [0, 1, 2, 3, 4].all (dealsMatchPools large) = true)
    {ℓ : Nat} (hℓ : ℓ ≤ 4) : dealsMatchPools large ℓ = true := by
  exact List.all_eq_true.mp h ℓ (by simp only [List.mem_cons, List.not_mem_nil]; omega)

theorem stats_std (ℓ : Nat) (hℓ : ℓ ≤ 4) : stats standardLarge ℓ =
    [(598427, 5622026), (255316, 1255574), (125207, 472118), (62029, 216116), (5735, 16307)].getD ℓ (0, 0) := by
  have h := stats_standard
  simp only [List.map_cons, List.map_nil, List.cons.injEq] at h
  rcases (by omega : ℓ = 0 ∨ ℓ = 1 ∨ ℓ = 2 ∨ ℓ = 3 ∨ ℓ = 4) with rfl | rfl | rfl | rfl | rfl <;> simp [h]

theorem stats_nas (ℓ : Nat) (hℓ : ℓ ≤ 4) : stats nastyLarge ℓ =
    [(598427, 5622026), (314793, 1758354), (60172, 204175), (6759, 16914), (501, 765)].getD ℓ (0, 0) := by
  have h := stats_nasty
  simp only [List.map_cons, List.map_nil, List.cons.injEq] at h
  rcases (by omega : ℓ = 0 ∨ ℓ = 1 ∨ ℓ = 2 ∨ ℓ = 3 ∨ ℓ = 4) with rfl | rfl | rfl | rfl | rfl <;> simp [h]

theorem length_unsolvablePairs_pools (large : List Nat) (ℓ : Nat) :
    (unsolvablePairs (pools large ℓ)).length = (stats large ℓ).1 := by
  rw [length_unsolvablePairs, stats_eq]

/-! State the main results for the standard game -/

/-- Count the unsolvable instances among the 8,548,200 of the standard game -/
theorem unsolvable_count : (unsolvablePairs gamePools).length = 380523 := by
  rw [length_unsolvablePairs, gamePools, List.map_append, List.sum_append]
  rw [← length_unsolvablePairs, ← length_unsolvablePairs, length_unsolvablePairs_pools,
    length_unsolvablePairs_pools, stats_std 1 (by omega), stats_std 2 (by omega)]
  rfl

/-- Give the probability that a dealt standard round has no exact solution -/
theorem gameMissProb_eq : gameMissProb = 16970693 / 837216000 := by
  unfold gameMissProb
  rw [missProb_eq (dealsMatch_of_all dealsMatch_standard (ℓ := 1) (by omega)),
    missProb_eq (dealsMatch_of_all dealsMatch_standard (ℓ := 2) (by omega)),
    stats_std 1 (by omega), stats_std 2 (by omega)]
  decide +kernel

/-- Express the same probability with the pool weights `½ · ∏ C(2, cᵢ) / C(20, k) / C(4, ℓ)` -/
theorem gameMissProb_eq_weighted : gameMissProb =
    ((pools standardLarge 1).map fun P => (1 / 2) * weight standardLarge 1 P * ((missCount P : Rat) / 900)).sum +
    ((pools standardLarge 2).map fun P => (1 / 2) * weight standardLarge 2 P * ((missCount P : Rat) / 900)).sum := by
  unfold gameMissProb
  rw [missProb_eq_weighted (dealsMatch_of_all dealsMatch_standard (ℓ := 1) (by omega)) (by decide),
    missProb_eq_weighted (dealsMatch_of_all dealsMatch_standard (ℓ := 2) (by omega)) (by decide)]
  simp only [Rat.mul_assoc]
  rw [sum_mul_left, sum_mul_left]
  grind

/-- Show that the game's pool weights sum to one -/
theorem gameWeights_sum_eq_one :
    ((pools standardLarge 1).map fun P => (1 / 2) * weight standardLarge 1 P).sum +
    ((pools standardLarge 2).map fun P => (1 / 2) * weight standardLarge 2 P).sum = 1 := by
  rw [sum_mul_left, sum_mul_left,
    weights_sum_eq_one (dealsMatch_of_all dealsMatch_standard (ℓ := 1) (by omega)) (by decide),
    weights_sum_eq_one (dealsMatch_of_all dealsMatch_standard (ℓ := 2) (by omega)) (by decide)]
  decide +kernel

/-! State the results for every number of large numbers and both large sets -/

/-- Count the unsolvable instances for each number of large numbers -/
theorem unsolvable_count_by_large :
    ((List.range 5).map fun ℓ => (unsolvablePairs (pools standardLarge ℓ)).length) =
      [598427, 255316, 125207, 62029, 5735] ∧
    ((List.range 5).map fun ℓ => (unsolvablePairs (pools nastyLarge ℓ)).length) =
      [598427, 314793, 60172, 6759, 501] := by
  simp only [length_unsolvablePairs_pools]
  simp [List.range_succ, stats_std, stats_nas]

/-- Give the probability of no exact solution for each number of large numbers with the standard set -/
theorem missProb_standard :
    ((List.range 5).map (missProb standardLarge)) =
      [2811013 / 17442000, 627787 / 27907200, 236059 / 13081500, 54029 / 1026000, 16307 / 171000] := by
  simp only [List.range_succ, List.range_zero, List.nil_append, List.cons_append, List.map_cons, List.map_nil]
  rw [missProb_eq (dealsMatch_of_all dealsMatch_standard (ℓ := 0) (by omega)),
    missProb_eq (dealsMatch_of_all dealsMatch_standard (ℓ := 1) (by omega)),
    missProb_eq (dealsMatch_of_all dealsMatch_standard (ℓ := 2) (by omega)),
    missProb_eq (dealsMatch_of_all dealsMatch_standard (ℓ := 3) (by omega)),
    missProb_eq (dealsMatch_of_all dealsMatch_standard (ℓ := 4) (by omega)),
    stats_std 0 (by omega), stats_std 1 (by omega), stats_std 2 (by omega), stats_std 3 (by omega),
    stats_std 4 (by omega)]
  decide +kernel

/-- Give the probability of no exact solution for each number of large numbers with the nasty set -/
theorem missProb_nasty :
    ((List.range 5).map (missProb nastyLarge)) =
      [2811013 / 17442000, 293059 / 9302400, 8167 / 1046520, 2819 / 684000, 17 / 3800] := by
  simp only [List.range_succ, List.range_zero, List.nil_append, List.cons_append, List.map_cons, List.map_nil]
  rw [missProb_eq (dealsMatch_of_all dealsMatch_nasty (ℓ := 0) (by omega)),
    missProb_eq (dealsMatch_of_all dealsMatch_nasty (ℓ := 1) (by omega)),
    missProb_eq (dealsMatch_of_all dealsMatch_nasty (ℓ := 2) (by omega)),
    missProb_eq (dealsMatch_of_all dealsMatch_nasty (ℓ := 3) (by omega)),
    missProb_eq (dealsMatch_of_all dealsMatch_nasty (ℓ := 4) (by omega)),
    stats_nas 0 (by omega), stats_nas 1 (by omega), stats_nas 2 (by omega), stats_nas 3 (by omega),
    stats_nas 4 (by omega)]
  decide +kernel

end Countdown
