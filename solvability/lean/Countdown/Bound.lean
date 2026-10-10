import Countdown.Expr

/-! Prove the value bound of Proposition `prop:bound` under the looser game rules, which also covers the paper's restricted rules -/

namespace Countdown

theorem prod_append' (l₁ l₂ : List Nat) : (l₁ ++ l₂).prod = l₁.prod * l₂.prod := List.prod_append_nat

/-- Bound a value by the product of `pᵢ + 1` over the leaves of its expression, minus one -/
theorem eval_add_one_le_prod {p : List Nat} {e : Expr} {v : Nat} (h : e.eval p = some v) :
    v + 1 ≤ (e.leaves.map fun i => p.getD i 0 + 1).prod := by
  induction e generalizing v with
  | leaf i =>
    obtain ⟨hi, _⟩ := Expr.eval_leaf.mp h
    simp [Expr.leaves, List.getD_eq_getElem?_getD, hi]
  | node op l r ihl ihr =>
    obtain ⟨a, b, ha, hb, hop, _⟩ := Expr.eval_node.mp h
    have hA := ihl ha
    have hB := ihr hb
    have hv : v ≤ a * b + a + b := by
      cases op <;> simp only [Op.apply] at hop
      · cases hop; omega
      · split at hop
        · cases hop; omega
        · simp at hop
      · cases hop; omega
      · split at hop
        · cases hop
          have := Nat.div_le_self a b
          omega
        · simp at hop
    simp only [Expr.leaves, List.map_append, prod_append']
    have hmul := Nat.mul_le_mul hA hB
    have : (a + 1) * (b + 1) = a * b + a + b + 1 := by
      rw [Nat.add_mul, Nat.mul_add, Nat.mul_one, Nat.one_mul]; omega
    omega

end Countdown
