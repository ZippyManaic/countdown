import Countdown.Expr

/-! Normalise a solution so that no node equals a child in value and no proper subexpression already lies in the target set -/

namespace Countdown.Sat

open Countdown Expr

variable (p : List Nat)

/-- Require every node to differ in value from both of its children -/
def Tight : Expr → Prop
  | .leaf _ => True
  | .node op l r => Tight l ∧ Tight r ∧
      ∀ a b v, l.eval p = some a → r.eval p = some b → (Expr.node op l r).eval p = some v → v ≠ a ∧ v ≠ b

/-- Replace each node whose value equals a child's value by that child, working from the leaves up -/
def prune : Expr → Expr
  | .leaf i => .leaf i
  | .node op l r =>
    if (Expr.node op (prune l) (prune r)).eval p = (prune l).eval p then prune l
    else if (Expr.node op (prune l) (prune r)).eval p = (prune r).eval p then prune r
    else .node op (prune l) (prune r)

variable {p}

/-- Show that pruning keeps the value, uses a sublist of the leaves and makes the expression tight -/
theorem prune_spec {e : Expr} {v : Nat} (h : e.eval p = some v) :
    (prune p e).eval p = some v ∧ (prune p e).leaves.Sublist e.leaves ∧ Tight p (prune p e) := by
  induction e generalizing v with
  | leaf i => exact ⟨h, List.Sublist.refl _, trivial⟩
  | node op l r ihl ihr =>
    obtain ⟨a, b, ha, hb, hop, hv⟩ := eval_node.mp h
    obtain ⟨hl1, hl2, hl3⟩ := ihl ha
    obtain ⟨hr1, hr2, hr3⟩ := ihr hb
    have hn : (Expr.node op (prune p l) (prune p r)).eval p = some v :=
      eval_node.mpr ⟨a, b, hl1, hr1, hop, hv⟩
    simp only [prune]
    split
    · rename_i h1
      exact ⟨h1.symm.trans hn, hl2.trans (List.sublist_append_left _ _), hl3⟩
    · split
      · rename_i _ h2
        exact ⟨h2.symm.trans hn, hr2.trans (List.sublist_append_right _ _), hr3⟩
      · rename_i h1 h2
        refine ⟨hn, hl2.append hr2, hl3, hr3, ?_⟩
        intro a' b' v' ha' hb' hv'
        rw [hl1] at ha'
        rw [hr1] at hb'
        rw [hn] at hv'
        cases ha'; cases hb'; cases hv'
        rw [hn, hl1] at h1
        rw [hn, hr1] at h2
        exact ⟨fun h => h1 (h ▸ rfl), fun h => h2 (h ▸ rfl)⟩

variable (p)

/-- Test whether an expression evaluates to a value in the set -/
def hit (S : Nat → Bool) (e : Expr) : Bool :=
  match e.eval p with
  | some v => S v
  | none => false

/-- Require that no subexpression, including the whole, evaluates into the set -/
def Clean (S : Nat → Bool) : Expr → Prop
  | .leaf i => hit p S (.leaf i) = false
  | .node op l r => Clean S l ∧ Clean S r ∧ hit p S (.node op l r) = false

/-- Return the first subexpression in post-order that evaluates into the set -/
def find (S : Nat → Bool) : Expr → Option Expr
  | .leaf i => if hit p S (.leaf i) then some (.leaf i) else none
  | .node op l r =>
    match find S l with
    | some x => some x
    | none =>
      match find S r with
      | some x => some x
      | none => if hit p S (.node op l r) then some (.node op l r) else none

/-- Require the children of a node to be clean -/
def KidsClean (S : Nat → Bool) : Expr → Prop
  | .leaf _ => True
  | .node _ l r => Clean p S l ∧ Clean p S r

variable {p}

theorem clean_hit {S : Nat → Bool} {e : Expr} (h : Clean p S e) : hit p S e = false := by
  cases e with
  | leaf i => exact h
  | node op l r => exact h.2.2

theorem find_none {S : Nat → Bool} {e : Expr} (h : find p S e = none) : Clean p S e := by
  induction e with
  | leaf i =>
    simp only [find] at h
    split at h
    · simp at h
    · rename_i hh
      simpa [Clean] using hh
  | node op l r ihl ihr =>
    simp only [find] at h
    split at h
    · simp at h
    · rename_i hl
      split at h
      · simp at h
      · rename_i hr
        split at h
        · simp at h
        · rename_i hh
          exact ⟨ihl hl, ihr hr, by simpa using hh⟩

/-- Show that a found subexpression evaluates into the set, has clean children and inherits leaves and tightness -/
theorem find_some {S : Nat → Bool} {e x : Expr} (h : find p S e = some x) (ht : Tight p e) :
    hit p S x = true ∧ KidsClean p S x ∧ x.leaves.Sublist e.leaves ∧ Tight p x := by
  induction e with
  | leaf i =>
    simp only [find] at h
    split at h
    · cases h
      rename_i hh
      exact ⟨hh, trivial, List.Sublist.refl _, ht⟩
    · simp at h
  | node op l r ihl ihr =>
    simp only [find] at h
    split at h
    · rename_i x' hl
      cases h
      obtain ⟨h1, h2, h3, h4⟩ := ihl hl ht.1
      exact ⟨h1, h2, h3.trans (List.sublist_append_left _ _), h4⟩
    · rename_i hl
      split at h
      · rename_i x' hr
        cases h
        obtain ⟨h1, h2, h3, h4⟩ := ihr hr ht.2.1
        exact ⟨h1, h2, h3.trans (List.sublist_append_right _ _), h4⟩
      · rename_i hr
        split at h
        · cases h
          rename_i hh
          exact ⟨hh, ⟨find_none hl, find_none hr⟩, List.Sublist.refl _, ht⟩
        · simp at h

theorem find_isSome {S : Nat → Bool} {e : Expr} (h : hit p S e = true) : ∃ x, find p S e = some x := by
  cases hf : find p S e with
  | some x => exact ⟨x, rfl⟩
  | none => rw [clean_hit (find_none hf)] at h; cases h

end Countdown.Sat
