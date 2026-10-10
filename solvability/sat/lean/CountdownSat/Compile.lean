import Countdown.Bound
import CountdownSat.Normal

/-! Compile an expression into a post-order straight-line program over natural numbers and prove its invariants -/

namespace Countdown.Sat

open Countdown Expr

/-- Record one natural-number program step with operand registers, operation, operand values and result -/
structure NStep where
  a : Nat
  b : Nat
  op : Op
  va : Nat
  vb : Nat
  v : Nat

/-- Mark addition and multiplication as the commutative operations -/
def opComm : Op → Bool
  | .add => true
  | .mul => true
  | _ => false

/-- Build a step and put the operands of a commutative operation in register order -/
def mkStep (op : Op) (ra va rb vb v : Nat) : NStep :=
  if opComm op && rb < ra then ⟨rb, ra, op, vb, va, v⟩ else ⟨ra, rb, op, va, vb, v⟩

variable (p : List Nat)

/-- Return the register holding the value, the value and the steps, numbering new registers from `base` -/
def compile : Expr → Nat → Nat × Nat × List NStep
  | .leaf i, _ => (i, p.getD i 0, [])
  | .node op l r, base =>
    (base + (compile l base).2.2.length + (compile r (base + (compile l base).2.2.length)).2.2.length,
     (op.apply (compile l base).2.1 (compile r (base + (compile l base).2.2.length)).2.1).getD 0,
     (compile l base).2.2 ++ (compile r (base + (compile l base).2.2.length)).2.2 ++
       [mkStep op (compile l base).1 (compile l base).2.1
          (compile r (base + (compile l base).2.2.length)).1 (compile r (base + (compile l base).2.2.length)).2.1
          ((op.apply (compile l base).2.1 (compile r (base + (compile l base).2.2.length)).2.1).getD 0)])

/-- List the operand registers of all steps in slot order -/
def ops : List NStep → List Nat
  | [] => []
  | s :: S => s.a :: s.b :: ops S

/-- Bound values by the product of `pᵢ + 1` over a list of positions as in `eval_add_one_le_prod` -/
def prodL (l : List Nat) : Nat := (l.map fun i => p.getD i 0 + 1).prod

/-- State that register `j` holds `val` when read by step `k`, either as a pool number or as an earlier result -/
def RegOK (base : Nat) (S : List NStep) (k j val : Nat) : Prop :=
  (j < 6 ∧ val = p.getD j 0) ∨ (∃ m, j = base + m ∧ m < k ∧ S[m]?.map NStep.v = some val)

/-- State the arithmetic meaning of a step in the form used by the bit-vector encoding -/
def Sem (s : NStep) : Prop :=
  0 < s.v ∧ s.v ≠ s.va ∧ s.v ≠ s.vb ∧ (opComm s.op = true → s.a ≤ s.b) ∧
  match s.op with
  | .add => s.vb + s.va = s.v
  | .sub => s.vb + s.v = s.va
  | .mul => s.vb * s.va = s.v
  | .div => s.vb * s.v = s.va

variable {p}

theorem ops_append (A B : List NStep) : ops (A ++ B) = ops A ++ ops B := by
  induction A with
  | nil => rfl
  | cons s A ih => simp [ops, ih]

theorem length_ops (S : List NStep) : (ops S).length = 2 * S.length := by
  induction S with
  | nil => rfl
  | cons s S ih => simp [ops, ih]; omega

theorem ops_getElem?_even (S : List NStep) (k : Nat) : (ops S)[2 * k]? = S[k]?.map NStep.a := by
  induction S generalizing k with
  | nil => simp [ops]
  | cons s S ih =>
    cases k with
    | zero => simp [ops]
    | succ k =>
      have : 2 * (k + 1) = 2 * k + 2 := by omega
      simp [ops, this, ih]

theorem ops_getElem?_odd (S : List NStep) (k : Nat) : (ops S)[2 * k + 1]? = S[k]?.map NStep.b := by
  induction S generalizing k with
  | nil => simp [ops]
  | cons s S ih =>
    cases k with
    | zero => simp [ops]
    | succ k =>
      have : 2 * (k + 1) + 1 = 2 * k + 1 + 2 := by omega
      simp [ops, this, ih]

theorem compile_leaf (i base : Nat) : compile p (.leaf i) base = (i, p.getD i 0, []) := rfl

theorem compile_val {e : Expr} {v : Nat} (base : Nat) (h : e.eval p = some v) : (compile p e base).2.1 = v := by
  induction e generalizing v base with
  | leaf i =>
    obtain ⟨hi, _⟩ := eval_leaf.mp h
    simp [compile, List.getD_eq_getElem?_getD, hi]
  | node op l r ihl ihr =>
    obtain ⟨a, b, ha, hb, hop, _⟩ := eval_node.mp h
    simp only [compile, ihl base ha, ihr _ hb, hop, Option.getD_some]

theorem compile_node_len (op : Op) (l r : Expr) (base : Nat) :
    (compile p (.node op l r) base).2.2.length =
      (compile p l base).2.2.length + (compile p r (base + (compile p l base).2.2.length)).2.2.length + 1 := by
  simp [compile]; omega

theorem compile_node_root (op : Op) (l r : Expr) (base : Nat) :
    (compile p (.node op l r) base).1 + 1 = base + (compile p (.node op l r) base).2.2.length := by
  rw [compile_node_len]; simp only [compile]; omega

/-- Show that the last step of a compiled node computes the node's value -/
theorem compile_node_last (op : Op) (l r : Expr) (base : Nat) :
    (compile p (.node op l r) base).2.2[(compile p (.node op l r) base).2.2.length - 1]?.map NStep.v =
      some (compile p (.node op l r) base).2.1 := by
  rw [compile_node_len]
  simp only [compile]
  rw [List.getElem?_append_right (by simp)]
  simp [mkStep]
  split <;> rfl

theorem compile_leaf_or_node (e : Expr) (base : Nat) :
    ((compile p e base).2.2 = [] ∧ (∃ i, e = .leaf i ∧ (compile p e base).1 = i)) ∨
    ((compile p e base).2.2 ≠ [] ∧ (compile p e base).1 + 1 = base + (compile p e base).2.2.length ∧
      (compile p e base).2.2[(compile p e base).2.2.length - 1]?.map NStep.v = some (compile p e base).2.1) := by
  cases e with
  | leaf i => exact Or.inl ⟨rfl, i, rfl, rfl⟩
  | node op l r =>
    refine Or.inr ⟨?_, compile_node_root op l r base, compile_node_last op l r base⟩
    intro h
    have := congrArg List.length h
    rw [compile_node_len] at this
    simp at this

theorem mkStep_perm (op : Op) (ra va rb vb v : Nat) :
    [(mkStep op ra va rb vb v).a, (mkStep op ra va rb vb v).b].Perm [ra, rb] := by
  unfold mkStep
  split
  · exact List.Perm.swap _ _ _
  · exact List.Perm.refl _

/-- Show that the operand registers plus the root are exactly the leaves plus the new registers -/
theorem compile_perm (e : Expr) (base : Nat) :
    (ops (compile p e base).2.2 ++ [(compile p e base).1]).Perm
      (e.leaves ++ List.range' base (compile p e base).2.2.length) := by
  induction e generalizing base with
  | leaf i => simp [compile, ops, leaves]
  | node op l r ihl ihr =>
    rw [compile_node_len]
    have hl := List.perm_iff_count.mp (ihl base)
    have hr := List.perm_iff_count.mp (ihr (base + (compile p l base).2.2.length))
    apply List.perm_iff_count.mpr
    intro x
    have hs := List.perm_iff_count.mp (mkStep_perm op (compile p l base).1 (compile p l base).2.1
      (compile p r (base + (compile p l base).2.2.length)).1 (compile p r (base + (compile p l base).2.2.length)).2.1
      ((op.apply (compile p l base).2.1 (compile p r (base + (compile p l base).2.2.length)).2.1).getD 0)) x
    have hx := hl x
    have hy := hr x
    rw [← List.range'_append_1 (m := _ + _) (n := 1), ← List.range'_append_1]
    simp only [compile, ops_append, leaves, List.count_append] at hx hy hs ⊢
    generalize (compile p l base) = cl at hx hy hs ⊢
    generalize (compile p r (base + cl.2.2.length)) = cr at hx hy hs ⊢
    simp only [ops, List.count_cons, List.count_nil, List.range'_one, Nat.add_assoc] at hx hy hs ⊢
    omega

/-- Lift a register fact for the left subprogram into the whole program -/
theorem RegOK.mono {base k j val : Nat} {S T : List NStep} (h : RegOK p base S k j val) (hk : k ≤ S.length) :
    RegOK p base (S ++ T) k j val := by
  rcases h with h | ⟨m, h1, h2, h3⟩
  · exact Or.inl h
  · exact Or.inr ⟨m, h1, h2, by rw [List.getElem?_append_left (by omega)]; exact h3⟩

/-- Lift a register fact for a later subprogram into the whole program -/
theorem RegOK.shift {base k j val : Nat} {A S : List NStep} (h : RegOK p (base + A.length) S k j val) :
    RegOK p base (A ++ S) (A.length + k) j val := by
  rcases h with h | ⟨m, h1, h2, h3⟩
  · exact Or.inl h
  · refine Or.inr ⟨A.length + m, by omega, by omega, ?_⟩
    rw [List.getElem?_append_right (by omega)]
    simpa using h3

/-- Collect the per-step facts that the bit-vector encoding needs -/
def StepInv (p : List Nat) (base : Nat) (S : List NStep) (bound k : Nat) (s : NStep) : Prop :=
  RegOK p base S k s.a s.va ∧ RegOK p base S k s.b s.vb ∧
  (6 ≤ s.a ∨ 6 ≤ s.b → s.a + 1 = base + k ∨ s.b + 1 = base + k) ∧ Sem s ∧
  s.v + 1 ≤ bound ∧ s.va + 1 ≤ bound ∧ s.vb + 1 ≤ bound

theorem prodL_append (l₁ l₂ : List Nat) : prodL p (l₁ ++ l₂) = prodL p l₁ * prodL p l₂ := by
  simp [prodL, List.map_append]

theorem prodL_pos (l : List Nat) : 0 < prodL p l := by
  induction l with
  | nil => simp [prodL]
  | cons i l ih => simp only [prodL, List.map_cons, List.prod_cons] at ih ⊢; exact Nat.mul_pos (by omega) ih

theorem regOK_of_leaf_or_node {e : Expr} {v : Nat} (base : Nat) (h : e.eval p = some v)
    (hleaf : ∀ i ∈ e.leaves, i < 6) :
    ((compile p e base).2.2 = [] ∧ (compile p e base).1 < 6 ∧ v = p.getD (compile p e base).1 0) ∨
    ((compile p e base).2.2 ≠ [] ∧ (compile p e base).1 + 1 = base + (compile p e base).2.2.length ∧
      (compile p e base).2.2[(compile p e base).2.2.length - 1]?.map NStep.v = some v) := by
  rcases compile_leaf_or_node (p := p) e base with ⟨h1, i, rfl, h3⟩ | ⟨h1, h2, h3⟩
  · refine Or.inl ⟨h1, ?_, ?_⟩
    · rw [h3]; exact hleaf i (by simp [leaves])
    · rw [h3]; obtain ⟨hi, _⟩ := eval_leaf.mp h; simp [List.getD_eq_getElem?_getD, hi]
  · exact Or.inr ⟨h1, h2, by rw [h3, compile_val base h]⟩

/-- Prove the per-step invariant of a compiled tight expression whose leaves are pool positions -/
theorem compile_inv {e : Expr} {v : Nat} (base : Nat) (h : e.eval p = some v) (ht : Tight p e)
    (hleaf : ∀ i ∈ e.leaves, i < 6) :
    ∀ k s, (compile p e base).2.2[k]? = some s → StepInv p base (compile p e base).2.2 (prodL p e.leaves) k s := by
  induction e generalizing v base with
  | leaf i => intro k s hs; simp [compile] at hs
  | node op l r ihl ihr =>
    obtain ⟨a, b, ha, hb, hop, hv⟩ := eval_node.mp h
    have hll : ∀ i ∈ l.leaves, i < 6 := fun i hi => hleaf i (by simp [leaves, hi])
    have hrl : ∀ i ∈ r.leaves, i < 6 := fun i hi => hleaf i (by simp [leaves, hi])
    have hbl := prodL_pos (p := p) l.leaves
    have hbr := prodL_pos (p := p) r.leaves
    have hprod : prodL p (Expr.node op l r).leaves = prodL p l.leaves * prodL p r.leaves := by
      simp only [leaves, prodL_append]
    have hlb : prodL p l.leaves ≤ prodL p (Expr.node op l r).leaves := by
      rw [hprod]; exact Nat.le_mul_of_pos_right _ hbr
    have hrb : prodL p r.leaves ≤ prodL p (Expr.node op l r).leaves := by
      rw [hprod]; exact Nat.le_mul_of_pos_left _ hbl
    intro k s hs
    -- Name the pieces of the compiled node
    generalize hcl : compile p l base = cl at hs
    generalize hcr : compile p r (base + cl.2.2.length) = cr at hs
    have hS : (compile p (.node op l r) base).2.2 = cl.2.2 ++ cr.2.2 ++
        [mkStep op cl.1 cl.2.1 cr.1 cr.2.1 ((op.apply cl.2.1 cr.2.1).getD 0)] := by
      simp only [compile, hcl, hcr]
    simp only [compile, hcl, hcr] at hs
    rw [hS]
    have hva : cl.2.1 = a := hcl ▸ compile_val base ha
    have hvb : cr.2.1 = b := hcr ▸ compile_val _ hb
    have hvv : (op.apply cl.2.1 cr.2.1).getD 0 = v := by rw [hva, hvb, hop]; rfl
    by_cases hk1 : k < cl.2.2.length
    · -- Take a step of the left subprogram
      rw [List.append_assoc, List.getElem?_append_left hk1] at hs
      have hi := ihl base ha ht.1 hll k s (by rw [hcl]; exact hs)
      rw [hcl] at hi
      obtain ⟨h1, h2, h3, h4, h5, h6, h7⟩ := hi
      rw [List.append_assoc]
      exact ⟨h1.mono (by omega), h2.mono (by omega), h3, h4, by omega, by omega, by omega⟩
    by_cases hk2 : k < cl.2.2.length + cr.2.2.length
    · -- Take a step of the right subprogram
      rw [List.getElem?_append_left (by simpa using hk2), List.getElem?_append_right (by omega)] at hs
      have hi := ihr (base + cl.2.2.length) hb ht.2.1 hrl (k - cl.2.2.length) s (by rw [hcr]; exact hs)
      rw [hcr] at hi
      obtain ⟨h1, h2, h3, h4, h5, h6, h7⟩ := hi
      have e1 := (h1.shift (A := cl.2.2)).mono (T := [mkStep op cl.1 cl.2.1 cr.1 cr.2.1 ((op.apply cl.2.1 cr.2.1).getD 0)]) (by simp; omega)
      have e2 := (h2.shift (A := cl.2.2)).mono (T := [mkStep op cl.1 cl.2.1 cr.1 cr.2.1 ((op.apply cl.2.1 cr.2.1).getD 0)]) (by simp; omega)
      have hk3 : cl.2.2.length + (k - cl.2.2.length) = k := by omega
      rw [hk3] at e1 e2
      refine ⟨e1, e2, ?_, h4, by omega, by omega, by omega⟩
      intro h0
      rcases h3 h0 with h3 | h3
      · left; omega
      · right; omega
    · -- Take the root step
      have hk : k = cl.2.2.length + cr.2.2.length := by
        have := List.getElem?_eq_some_iff.mp hs
        obtain ⟨hlt, _⟩ := this
        simp at hlt; omega
      rw [hk, List.getElem?_append_right (by simp)] at hs
      simp at hs
      subst hs
      subst hva hvb
      -- Describe the two operand registers
      have hL := regOK_of_leaf_or_node (p := p) base ha hll
      have hR := regOK_of_leaf_or_node (p := p) (base + cl.2.2.length) hb hrl
      rw [hcl] at hL
      rw [hcr] at hR
      have hT := ht.2.2 _ _ _ ha hb h
      have hA : RegOK p base (cl.2.2 ++ cr.2.2 ++ [mkStep op cl.1 cl.2.1 cr.1 cr.2.1
          ((op.apply cl.2.1 cr.2.1).getD 0)]) k cl.1 cl.2.1 := by
        rcases hL with ⟨_, h2, h3⟩ | ⟨h1, h2, h3⟩
        · exact Or.inl ⟨h2, h3⟩
        · have hpos := List.length_pos_iff.mpr h1
          refine Or.inr ⟨cl.2.2.length - 1, by omega, by omega, ?_⟩
          rw [List.append_assoc, List.getElem?_append_left (by omega)]
          exact h3
      have hB : RegOK p base (cl.2.2 ++ cr.2.2 ++ [mkStep op cl.1 cl.2.1 cr.1 cr.2.1
          ((op.apply cl.2.1 cr.2.1).getD 0)]) k cr.1 cr.2.1 := by
        rcases hR with ⟨_, h2, h3⟩ | ⟨h1, h2, h3⟩
        · exact Or.inl ⟨h2, h3⟩
        · have hpos := List.length_pos_iff.mpr h1
          refine Or.inr ⟨cl.2.2.length + cr.2.2.length - 1, by omega, by omega, ?_⟩
          rw [List.getElem?_append_left (by simp; omega), List.getElem?_append_right (by omega)]
          have : cl.2.2.length + cr.2.2.length - 1 - cl.2.2.length = cr.2.2.length - 1 := by omega
          rw [this]; exact h3
      -- Bound the values by the product over the leaves
      have hBv : _ ≤ prodL p (Expr.node op l r).leaves := eval_add_one_le_prod h
      have hBa := Nat.le_trans (eval_add_one_le_prod ha) hlb
      have hBb := Nat.le_trans (eval_add_one_le_prod hb) hrb
      -- Show the post-order property of the root step
      have hpo : 6 ≤ cl.1 ∨ 6 ≤ cr.1 → cl.1 + 1 = base + k ∨ cr.1 + 1 = base + k := by
        intro h0
        rcases hR with ⟨hr1, hr2, _⟩ | ⟨_, hr2, _⟩
        · rcases hL with ⟨_, hl2, _⟩ | ⟨_, hl2, _⟩
          · omega
          · left; rw [hr1, List.length_nil] at hk; omega
        · right; omega
      generalize cl.2.2 ++ cr.2.2 ++ [mkStep op cl.1 cl.2.1 cr.1 cr.2.1 ((op.apply cl.2.1 cr.2.1).getD 0)] = Sf
        at hA hB ⊢
      unfold mkStep
      split
      · rename_i hc
        unfold StepInv Sem
        dsimp only
        rw [hvv]
        simp only [Bool.and_eq_true, decide_eq_true_eq] at hc
        refine ⟨hB, hA, by omega, ?_, by omega, by omega, by omega⟩
        refine ⟨by omega, hT.2, hT.1, fun _ => by omega, ?_⟩
        cases op <;> simp [opComm] at hc <;> simp only [Op.apply, Option.some.injEq] at hop
        · omega
        · rw [← hop]
      · rename_i hc
        unfold StepInv Sem
        dsimp only
        rw [hvv]
        refine ⟨hA, hB, hpo, ?_, by omega, by omega, by omega⟩
        refine ⟨by omega, hT.1, hT.2, ?_, ?_⟩
        · intro hcomm; simp [hcomm] at hc; omega
        · cases op <;> simp only [Op.apply] at hop
          · simp at hop; omega
          · split at hop
            · simp at hop; omega
            · simp at hop
          · simp at hop; rw [Nat.mul_comm]; exact hop
          · split at hop
            · rename_i hd
              simp at hop
              rw [← hop]; exact Nat.mul_div_cancel' hd.2
            · simp at hop

/-- Show that every step of a compiled clean expression has a value outside the set -/
theorem compile_clean {S : Nat → Bool} {e : Expr} {v : Nat} (base : Nat) (h : e.eval p = some v)
    (hc : Clean p S e) : ∀ s ∈ (compile p e base).2.2, S s.v = false := by
  induction e generalizing v base with
  | leaf i => intro s hs; simp [compile] at hs
  | node op l r ihl ihr =>
    obtain ⟨a, b, ha, hb, hop, hv⟩ := eval_node.mp h
    intro s hs
    simp only [compile, List.mem_append, List.mem_singleton] at hs
    rcases hs with (hs | hs) | hs
    · exact ihl base ha hc.1 s hs
    · exact ihr _ hb hc.2.1 s hs
    · have h2 := hc.2.2
      simp only [hit, h] at h2
      subst hs
      rw [compile_val base ha, compile_val _ hb, hop]
      unfold mkStep
      split <;> exact h2

end Countdown.Sat
