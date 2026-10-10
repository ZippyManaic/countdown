/-! Define expressions over pool positions under the game's rules, where operands come in either order and every value including each leaf must be a positive integer -/

namespace Countdown

/-- List the four arithmetic operations of the game -/
inductive Op where
  | add | sub | mul | div
  deriving DecidableEq, Repr

/-- Apply an operation to natural numbers giving `none` for a non-positive difference or an inexact quotient -/
def Op.apply : Op → Nat → Nat → Option Nat
  | .add, a, b => some (a + b)
  | .sub, a, b => if b < a then some (a - b) else none
  | .mul, a, b => some (a * b)
  | .div, a, b => if 0 < b ∧ b ∣ a then some (a / b) else none

/-- Keep a value only if it is a positive integer -/
def pos (v : Nat) : Option Nat := if 0 < v then some v else none

/-- Represent an arithmetic expression whose leaves are positions in the pool -/
inductive Expr where
  | leaf (i : Nat)
  | node (op : Op) (l r : Expr)
  deriving DecidableEq, Repr

namespace Expr

/-- Evaluate an expression over a pool returning `none` as soon as any value is not a positive integer -/
def eval (p : List Nat) : Expr → Option Nat
  | leaf i => p[i]?.bind pos
  | node op l r =>
    match l.eval p, r.eval p with
    | some a, some b => (op.apply a b).bind pos
    | _, _ => none

/-- List the pool positions used by the leaves from left to right -/
def leaves : Expr → List Nat
  | leaf i => [i]
  | node _ l r => l.leaves ++ r.leaves

/-- Require every pool position to be used at most once -/
def Legal (e : Expr) : Prop := e.leaves.Nodup

instance : DecidablePred Legal := fun e => inferInstanceAs (Decidable e.leaves.Nodup)

/-- Encode the set of leaf positions as a bit mask -/
def mask : Expr → Nat
  | leaf i => 2 ^ i
  | node _ l r => l.mask ||| r.mask

end Expr

/-- State that some legal expression over the pool evaluates exactly to the target -/
def Solvable (p : List Nat) (t : Nat) : Prop :=
  ∃ e : Expr, e.Legal ∧ e.eval p = some t

namespace Expr

theorem mem_leaves_iff_testBit (e : Expr) (i : Nat) : i ∈ e.leaves ↔ e.mask.testBit i = true := by
  induction e with
  | leaf j => simp [leaves, mask, Nat.testBit_two_pow, eq_comm]
  | node _ l r ihl ihr => simp [leaves, mask, ihl, ihr]

theorem leaves_ne_nil (e : Expr) : e.leaves ≠ [] := by
  induction e with
  | leaf j => simp [leaves]
  | node _ l r ihl _ => simp [leaves, ihl]

theorem mask_ne_zero (e : Expr) : e.mask ≠ 0 := by
  intro h
  obtain ⟨i, hi⟩ := List.exists_mem_of_ne_nil _ e.leaves_ne_nil
  rw [mem_leaves_iff_testBit, h] at hi
  simp at hi

theorem and_eq_zero_iff (x y : Nat) : x &&& y = 0 ↔ ∀ i, ¬ (x.testBit i = true ∧ y.testBit i = true) := by
  constructor
  · intro h i ⟨hx, hy⟩
    have := congrArg (fun n => n.testBit i) h
    simp [hx, hy] at this
  · intro h
    apply Nat.eq_of_testBit_eq
    intro i
    have := h i
    simp only [Nat.testBit_and, Nat.zero_testBit]
    cases hx : x.testBit i <;> cases hy : y.testBit i <;> simp_all

theorem legal_leaf (i : Nat) : (leaf i).Legal := by simp [Legal, leaves]

theorem legal_node_iff (op : Op) (l r : Expr) :
    (node op l r).Legal ↔ l.Legal ∧ r.Legal ∧ l.mask &&& r.mask = 0 := by
  simp only [Legal, leaves, List.nodup_append, and_eq_zero_iff, ← mem_leaves_iff_testBit]
  constructor
  · rintro ⟨h1, h2, h3⟩
    exact ⟨h1, h2, fun i ⟨hl, hr⟩ => h3 i hl i hr rfl⟩
  · rintro ⟨h1, h2, h3⟩
    exact ⟨h1, h2, fun a ha b hb hab => h3 a ⟨ha, hab ▸ hb⟩⟩

theorem eval_pos {p : List Nat} {e : Expr} {v : Nat} (h : e.eval p = some v) : 0 < v := by
  cases e with
  | leaf i =>
    simp only [eval, Option.bind_eq_some_iff, pos] at h
    obtain ⟨_, _, h⟩ := h
    split at h <;> simp_all
  | node op l r =>
    simp only [eval] at h
    split at h
    · simp only [Option.bind_eq_some_iff, pos] at h
      obtain ⟨_, _, h⟩ := h
      split at h <;> simp_all
    · simp at h

theorem eval_leaf {p : List Nat} {i v : Nat} : (leaf i).eval p = some v ↔ p[i]? = some v ∧ 0 < v := by
  simp only [eval, Option.bind_eq_some_iff, pos]
  constructor
  · rintro ⟨w, hw, h⟩
    split at h <;> simp_all
  · rintro ⟨hw, hv⟩
    exact ⟨v, hw, by simp [hv]⟩

theorem eval_node {p : List Nat} {op : Op} {l r : Expr} {v : Nat} :
    (node op l r).eval p = some v ↔
      ∃ a b, l.eval p = some a ∧ r.eval p = some b ∧ op.apply a b = some v ∧ 0 < v := by
  simp only [eval]
  constructor
  · intro h
    split at h
    · rename_i a b ha hb
      simp only [Option.bind_eq_some_iff, pos] at h
      obtain ⟨w, hw, h⟩ := h
      split at h
      · cases h; exact ⟨a, b, ha, hb, hw, by assumption⟩
      · simp at h
    · simp at h
  · rintro ⟨a, b, ha, hb, hv, hpos⟩
    simp [ha, hb, hv, pos, hpos]

/-- Show that every leaf of an expression that evaluates lies inside the pool -/
theorem leaves_lt_of_eval {p : List Nat} {e : Expr} {v : Nat} (h : e.eval p = some v) :
    ∀ i ∈ e.leaves, i < p.length := by
  induction e generalizing v with
  | leaf j =>
    intro i hi
    simp [leaves] at hi
    subst hi
    rw [eval_leaf] at h
    exact (List.getElem?_eq_some_iff.mp h.1).1
  | node op l r ihl ihr =>
    obtain ⟨a, b, ha, hb, _⟩ := eval_node.mp h
    intro i hi
    simp only [leaves, List.mem_append] at hi
    rcases hi with hi | hi
    · exact ihl ha i hi
    · exact ihr hb i hi

theorem mask_lt_of_eval {p : List Nat} {e : Expr} {v : Nat} (h : e.eval p = some v) :
    e.mask < 2 ^ p.length := by
  apply Nat.lt_pow_two_of_testBit
  intro i hi
  cases hb : e.mask.testBit i
  · rfl
  · have := leaves_lt_of_eval h i ((mem_leaves_iff_testBit e i).mpr hb)
    omega

/-! Show that relabelling positions preserves solvability so that the order of the pool is irrelevant -/

/-- Rename every leaf position through a function -/
def relabel (f : Nat → Nat) : Expr → Expr
  | leaf i => leaf (f i)
  | node op l r => node op (relabel f l) (relabel f r)

theorem leaves_relabel (f : Nat → Nat) (e : Expr) : (e.relabel f).leaves = e.leaves.map f := by
  induction e with
  | leaf i => rfl
  | node _ l r ihl ihr => simp [relabel, leaves, ihl, ihr]

theorem eval_relabel {p q : List Nat} {f : Nat → Nat} (hf : ∀ i, p[i]? = q[f i]?) (e : Expr) :
    (e.relabel f).eval q = e.eval p := by
  induction e with
  | leaf i => simp [relabel, eval, hf i]
  | node op l r ihl ihr => simp [relabel, eval, ihl, ihr]

theorem legal_relabel {f : Nat → Nat} (hf : ∀ i j, f i = f j → i = j) {e : Expr} (h : e.Legal) :
    (e.relabel f).Legal := by
  unfold Legal at *
  rw [leaves_relabel]
  exact List.Pairwise.map f (fun a b hab h2 => hab (hf a b h2)) h

end Expr

/-- Find an injective relabelling of positions that carries one pool onto a permutation of it -/
theorem exists_relabel_of_perm {p q : List Nat} (h : p.Perm q) :
    ∃ f : Nat → Nat, (∀ i j, f i = f j → i = j) ∧ ∀ i, p[i]? = q[f i]? := by
  induction h with
  | nil => exact ⟨id, fun _ _ h => h, fun _ => rfl⟩
  | cons x _ ih =>
    obtain ⟨f, hinj, hf⟩ := ih
    refine ⟨fun i => match i with | 0 => 0 | i + 1 => f i + 1, ?_, ?_⟩
    · intro i j hij
      cases i <;> cases j <;> simp_all
      exact hinj _ _ hij
    · intro i
      cases i <;> simp [hf]
  | swap x y l =>
    refine ⟨fun i => match i with | 0 => 1 | 1 => 0 | i + 2 => i + 2, ?_, ?_⟩
    · intro i j hij
      rcases i with _ | _ | i <;> rcases j with _ | _ | j <;> simp_all
    · intro i
      rcases i with _ | _ | i <;> simp
  | trans _ _ ih1 ih2 =>
    obtain ⟨f, hf1, hf2⟩ := ih1
    obtain ⟨g, hg1, hg2⟩ := ih2
    exact ⟨g ∘ f, fun i j h => hf1 _ _ (hg1 _ _ h), fun i => (hf2 i).trans (hg2 (f i))⟩

/-- Show that solvability depends only on the multiset of numbers in the pool and not on their order -/
theorem solvable_perm {p q : List Nat} (h : p.Perm q) (t : Nat) : Solvable p t ↔ Solvable q t := by
  have key : ∀ {p q : List Nat}, p.Perm q → Solvable p t → Solvable q t := by
    intro p q h ⟨e, he, hv⟩
    obtain ⟨f, hinj, hf⟩ := exists_relabel_of_perm h
    exact ⟨e.relabel f, Expr.legal_relabel hinj he, (Expr.eval_relabel hf e).trans hv⟩
  exact ⟨key h, key h.symm⟩

end Countdown
