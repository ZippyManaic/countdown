import Countdown.Solver

/-! Model a deal as an equally likely pair of a small-card subset and a large-number subset and enumerate the pools up to order, all parametrised by the large set and by `ℓ` -/

namespace Countdown

/-- List the standard four large numbers -/
def standardLarge : List Nat := [25, 50, 75, 100]

/-- List the large numbers of the two 2010 special episodes -/
def nastyLarge : List Nat := [12, 37, 62, 87]

/-- List the twenty small cards, two of each of 1 to 10, in ascending order -/
def deck : List Nat := (List.range 10).flatMap fun i => [i + 1, i + 1]

/-- List the targets 100 to 999 -/
def targets : List Nat := List.range' 100 900

/-- List every `k`-element sublist, so that distinct positions give distinct entries -/
def choose {α : Type} : Nat → List α → List (List α)
  | 0, _ => [[]]
  | _ + 1, [] => []
  | k + 1, x :: xs => (choose k xs).map (x :: ·) ++ choose (k + 1) xs

/-- List every deal of `ℓ` large numbers from `large` and `6 - ℓ` small cards as the dealt pool, one entry per pair of card subsets -/
def deals (large : List Nat) (ℓ : Nat) : List (List Nat) :=
  (choose (6 - ℓ) deck).flatMap fun S => (choose ℓ large).map fun L => S ++ L

/-- List the ascending multisets of size `k` over the given values using each value at most twice -/
def boundedMultisets : List Nat → Nat → List (List Nat)
  | [], 0 => [[]]
  | [], _ + 1 => []
  | x :: xs, k =>
    (List.range (min 2 k + 1)).flatMap fun c =>
      (boundedMultisets xs (k - c)).map (List.replicate c x ++ ·)

/-- List the pools with `ℓ` large numbers from `large` up to order, small numbers first as in `pools.py` -/
def pools (large : List Nat) (ℓ : Nat) : List (List Nat) :=
  (choose ℓ large).flatMap fun L =>
    (boundedMultisets ((List.range 10).map (· + 1)) (6 - ℓ)).map (· ++ L)

/-- List the pools the standard game deals, with one or two large numbers -/
def gamePools : List (List Nat) := pools standardLarge 1 ++ pools standardLarge 2

/-- Compute the binomial coefficient by Pascal's rule -/
def binom : Nat → Nat → Nat
  | _, 0 => 1
  | 0, _ + 1 => 0
  | n + 1, k + 1 => binom n k + binom n (k + 1)

/-- Count the ways the deck can supply the small numbers of a pool, that is `∏ C(2, cᵢ)` -/
def smallWays (P : List Nat) : Nat :=
  ((List.range 10).map fun i => binom 2 (P.count (i + 1))).foldr (· * ·) 1

/-- Weight a pool given `ℓ` large numbers as `∏ C(2, cᵢ) / C(20, 6 - ℓ) / C(|large|, ℓ)` -/
def weight (large : List Nat) (ℓ : Nat) (P : List Nat) : Rat :=
  (smallWays P : Rat) / (binom 20 (6 - ℓ) : Rat) / (binom large.length ℓ : Rat)

/-! Sum in parallel while proving the result equals the plain sum -/

/-- Split a list into consecutive chunks of length `n` -/
def chunks {α : Type} (n : Nat) : Nat → List α → List (List α)
  | 0, xs => [xs]
  | f + 1, xs => if xs.length ≤ n then [xs] else xs.take n :: chunks n f (xs.drop n)

theorem flatten_chunks {α : Type} (n f : Nat) (xs : List α) : (chunks n f xs).flatten = xs := by
  induction f generalizing xs with
  | zero => simp [chunks]
  | succ f ih =>
    simp only [chunks]
    split
    · simp
    · simp [ih]

/-- Sum `f` over a list, evaluating chunks of 16 elements as parallel tasks in compiled code -/
def parSum {α : Type} (f : α → Nat) (xs : List α) : Nat :=
  let tasks := (chunks 16 xs.length xs).map fun c => Task.spawn fun _ => (c.map f).sum
  (tasks.map Task.get).sum

theorem sum_map_flatten {α : Type} (f : α → Nat) (L : List (List α)) :
    (L.flatten.map f).sum = (L.map fun c => (c.map f).sum).sum := by
  induction L with
  | nil => rfl
  | cons c L ih =>
    simp only [List.flatten_cons, List.map_append, List.sum_append, List.map_cons, List.sum_cons, ih]

theorem parSum_eq {α : Type} (f : α → Nat) (xs : List α) : parSum f xs = (xs.map f).sum := by
  conv => rhs; rw [← flatten_chunks 16 xs.length xs]
  rw [sum_map_flatten]
  simp only [parSum, List.map_map, Function.comp_def]
  rfl

/-! Count the missed targets of a pool -/

theorem targets_length : targets.length = 900 := by simp [targets]

/-- Count the targets 100 to 999 that the pool cannot reach exactly, sharing one reachable set -/
def missCount (p : List Nat) : Nat :=
  let R := (reachable p).filter fun v => 100 ≤ v && v ≤ 999
  targets.countP fun t => !R.contains t

theorem missCount_eq (p : List Nat) :
    missCount p = (targets.filter fun t => ¬ Solvable p t).length := by
  rw [← List.countP_eq_length_filter]
  unfold missCount
  apply List.countP_congr
  intro t ht
  simp only [targets, List.mem_range'] at ht
  obtain ⟨i, hi, rfl⟩ := ht
  have key : ((reachable p).filter fun v => 100 ≤ v && v ≤ 999).contains (100 + 1 * i) = true ↔
      Solvable p (100 + 1 * i) := by
    rw [List.contains_iff_mem, List.mem_filter, mem_reachable]
    constructor
    · exact fun h => h.1
    · intro h; exact ⟨h, by simp; omega⟩
  cases h : ((reachable p).filter fun v => 100 ≤ v && v ≤ 999).contains (100 + 1 * i) <;>
    simp_all

/-- List the unsolvable pairs of a pool from a list and a target from 100 to 999 -/
def unsolvablePairs (ps : List (List Nat)) : List (List Nat × Nat) :=
  (ps.flatMap fun p => targets.map fun t => (p, t)).filter fun pt => ¬ Solvable pt.1 pt.2

theorem length_unsolvablePairs (ps : List (List Nat)) :
    (unsolvablePairs ps).length = (ps.map missCount).sum := by
  induction ps with
  | nil => rfl
  | cons p ps ih =>
    simp only [unsolvablePairs, List.flatMap_cons, List.filter_append, List.length_append,
      List.map_cons, List.sum_cons] at *
    rw [ih, missCount_eq, List.filter_map, List.length_map]
    rfl

/-! Regroup a sum over deals as a sum over pools -/

theorem sum_map_add' {α : Type} (l : List α) (f g : α → Nat) :
    (l.map fun a => f a + g a).sum = (l.map f).sum + (l.map g).sum := by
  induction l with
  | nil => rfl
  | cons a l ih => simp only [List.map_cons, List.sum_cons, ih]; omega

theorem sum_ite_eq {α : Type} [BEq α] [LawfulBEq α] (ys : List α) (x : α) (f : α → Nat) (hn : ys.Nodup) :
    (ys.map fun y => if (x == y) = true then f y else 0).sum = if x ∈ ys then f x else 0 := by
  induction ys with
  | nil => simp
  | cons y ys ih =>
    simp only [List.nodup_cons] at hn
    simp only [List.map_cons, List.sum_cons, ih hn.2, List.mem_cons]
    by_cases h : x = y
    · subst h; simp [hn.1]
    · simp [h]

/-- Regroup a sum over a list by the distinct values it takes -/
theorem sum_regroup {α : Type} [BEq α] [LawfulBEq α] (xs ys : List α) (f : α → Nat)
    (hn : ys.Nodup) (hsub : ∀ x ∈ xs, x ∈ ys) :
    (xs.map f).sum = (ys.map fun y => xs.count y * f y).sum := by
  induction xs with
  | nil =>
    simp only [List.map_nil, List.sum_nil, List.count_nil, Nat.zero_mul]
    clear hn hsub
    induction ys with
    | nil => rfl
    | cons y ys ih => simp only [List.map_cons, List.sum_cons, ← ih]; rfl
  | cons x xs ih =>
    have hx : x ∈ ys := hsub x (by simp)
    have hfun : (fun y => (x :: xs).count y * f y) =
        fun y => xs.count y * f y + (if (x == y) = true then f y else 0) := by
      funext y
      rw [List.count_cons, Nat.add_mul]
      by_cases h : x = y <;> simp [h]
    rw [hfun, sum_map_add', sum_ite_eq ys x f hn, ite_eq_left_of_eq_true _ _ (eq_true hx), ← ih (fun z hz => hsub z (by simp [hz]))]
    simp only [List.map_cons, List.sum_cons]
    omega

end Countdown

namespace Countdown

/-! Map in parallel while proving the result equals the plain map -/

/-- Map `f` over a list, evaluating chunks of 16 elements as parallel tasks in compiled code -/
def parMap {α β : Type} (f : α → β) (xs : List α) : List β :=
  let tasks := (chunks 16 xs.length xs).map fun c => Task.spawn fun _ => c.map f
  (tasks.map Task.get).flatten

theorem parMap_eq {α β : Type} (f : α → β) (xs : List α) : parMap f xs = xs.map f := by
  conv => rhs; rw [← flatten_chunks 16 xs.length xs]
  rw [List.map_flatten]
  simp only [parMap, List.map_map, Function.comp_def]
  rfl

theorem zipWith_map_map {α : Type} (xs : List α) (f g : α → Nat) :
    List.zipWith (· * ·) (xs.map g) (xs.map f) = xs.map fun x => g x * f x := by
  induction xs with
  | nil => rfl
  | cons x xs ih => simp [ih]

/-! Gather the statistics of a family of pools -/

/-- Compute the total and the deal-weighted total of missed targets over the pools with `ℓ` large numbers -/
def stats (large : List Nat) (ℓ : Nat) : Nat × Nat :=
  let ps := pools large ℓ
  let ms := parMap missCount ps
  (ms.sum, (List.zipWith (· * ·) (ps.map smallWays) ms).sum)

theorem stats_eq (large : List Nat) (ℓ : Nat) :
    stats large ℓ = (((pools large ℓ).map missCount).sum,
      ((pools large ℓ).map fun P => smallWays P * missCount P).sum) := by
  simp only [stats, parMap_eq, zipWith_map_map]

/-- Check that pools are distinct, every deal is one of them, each arises from exactly `smallWays` deals and the deals number `C(20, 6 - ℓ) · C(|large|, ℓ)` -/
def dealsMatchPools (large : List Nat) (ℓ : Nat) : Bool :=
  let ps := pools large ℓ
  let ds := deals large ℓ
  decide ps.Nodup && ds.all (· ∈ ps) && ps.all (fun P => ds.count P == smallWays P) &&
    ds.length == binom 20 (6 - ℓ) * binom large.length ℓ

theorem dealsMatchPools_spec {large : List Nat} {ℓ : Nat} (h : dealsMatchPools large ℓ = true) :
    (pools large ℓ).Nodup ∧ (∀ d ∈ deals large ℓ, d ∈ pools large ℓ) ∧
      (∀ P ∈ pools large ℓ, (deals large ℓ).count P = smallWays P) ∧
      (deals large ℓ).length = binom 20 (6 - ℓ) * binom large.length ℓ := by
  simp only [dealsMatchPools, Bool.and_eq_true, decide_eq_true_eq, List.all_eq_true, beq_iff_eq] at h
  obtain ⟨⟨⟨h1, h2⟩, h3⟩, h4⟩ := h
  exact ⟨h1, fun d hd => by simpa using h2 d hd, h3, h4⟩

/-- Turn a sum over deals into a sum over pools weighted by the number of deals giving each pool -/
theorem sum_deals_eq {large : List Nat} {ℓ : Nat} (h : dealsMatchPools large ℓ = true) (f : List Nat → Nat) :
    ((deals large ℓ).map f).sum = ((pools large ℓ).map fun P => smallWays P * f P).sum := by
  obtain ⟨hn, hsub, hcount, _⟩ := dealsMatchPools_spec h
  rw [sum_regroup _ _ f hn hsub]
  congr 1
  apply List.map_congr_left
  intro P hP
  rw [hcount P hP]

/-! Define the probability of no exact solution over deals -/

/-- Give the probability that a deal with `ℓ` large numbers from `large` has no exact solution, every pair of card subsets and every target from 100 to 999 being equally likely -/
noncomputable def missProb (large : List Nat) (ℓ : Nat) : Rat :=
  ((((deals large ℓ).map fun d => (targets.filter fun t => ¬ Solvable d t).length).sum : Nat) : Rat) /
    (((deals large ℓ).length * targets.length : Nat) : Rat)

/-- Give the game's probability of no exact solution, one or two large numbers being equally likely -/
noncomputable def gameMissProb : Rat := (missProb standardLarge 1 + missProb standardLarge 2) / 2

theorem missProb_eq {large : List Nat} {ℓ : Nat} (h : dealsMatchPools large ℓ = true) :
    missProb large ℓ =
      ((stats large ℓ).2 : Rat) / ((binom 20 (6 - ℓ) * binom large.length ℓ * 900 : Nat) : Rat) := by
  have hmap : ((deals large ℓ).map fun d => (targets.filter fun t => ¬ Solvable d t).length) =
      (deals large ℓ).map missCount := by
    apply List.map_congr_left; intro d _; rw [missCount_eq]
  unfold missProb
  rw [hmap, sum_deals_eq h, stats_eq, (dealsMatchPools_spec h).2.2.2, targets_length]

end Countdown
