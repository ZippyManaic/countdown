import CountdownSat.Enc
import CountdownSat.Compile

/-! Prove that the encoding is complete, so that an unsatisfiable instance shows that no target in the intervals is solvable -/

namespace Countdown.Sat

open Countdown Expr

/-! Unfold the bounded conjunctions and disjunctions -/

theorem ball_iff {n : Nat} {f : Nat → Bool} : ball n f = true ↔ ∀ k < n, f k = true := by
  induction n with
  | zero => simp [ball]
  | succ n ih =>
    simp only [ball, Bool.and_eq_true, ih]
    constructor
    · rintro ⟨h1, h2⟩ k hk
      by_cases h : k < n
      · exact h1 k h
      · have : k = n := by omega
        exact this ▸ h2
    · intro h
      exact ⟨fun k hk => h k (by omega), h n (by omega)⟩

theorem bany_iff {n : Nat} {f : Nat → Bool} : bany n f = true ↔ ∃ k < n, f k = true := by
  induction n with
  | zero => simp [bany]
  | succ n ih =>
    simp only [bany, Bool.or_eq_true, ih]
    constructor
    · rintro (⟨k, hk, h⟩ | h)
      · exact ⟨k, by omega, h⟩
      · exact ⟨n, by omega, h⟩
    · rintro ⟨k, hk, h⟩
      by_cases hk' : k < n
      · exact Or.inl ⟨k, hk', h⟩
      · have : k = n := by omega
        exact Or.inr (this ▸ h)

/-! Relate bit-vector operations on in-range literals to natural-number facts -/

theorem ofNat_inj {w a b : Nat} (ha : a < 2 ^ w) (hb : b < 2 ^ w) (h : BitVec.ofNat w a = BitVec.ofNat w b) :
    a = b := by
  have := congrArg BitVec.toNat h
  simpa [BitVec.toNat_ofNat, Nat.mod_eq_of_lt ha, Nat.mod_eq_of_lt hb] using this

theorem bne_ofNat {w a b : Nat} (ha : a < 2 ^ w) (hb : b < 2 ^ w) (h : a ≠ b) :
    (BitVec.ofNat w a != BitVec.ofNat w b) = true := by
  simp only [bne_iff_ne, ne_eq]
  exact fun h' => h (ofNat_inj ha hb h')

theorem ult_ofNat {w a b : Nat} (ha : a < 2 ^ w) (hb : b < 2 ^ w) :
    (BitVec.ofNat w a).ult (BitVec.ofNat w b) = decide (a < b) := by
  simp [BitVec.ult, BitVec.toNat_ofNat, Nat.mod_eq_of_lt ha, Nat.mod_eq_of_lt hb]

theorem ule_ofNat {w a b : Nat} (ha : a < 2 ^ w) (hb : b < 2 ^ w) :
    (BitVec.ofNat w a).ule (BitVec.ofNat w b) = decide (a ≤ b) := by
  simp [BitVec.ule, BitVec.toNat_ofNat, Nat.mod_eq_of_lt ha, Nat.mod_eq_of_lt hb]

theorem zext_ofNat {w v a : Nat} (ha : a < 2 ^ w) (hwv : w ≤ v) :
    (BitVec.ofNat w a).setWidth v = BitVec.ofNat v a := by
  have hav : a < 2 ^ v := Nat.lt_of_lt_of_le ha (Nat.pow_le_pow_right (by omega) hwv)
  apply BitVec.eq_of_toNat_eq
  simp [BitVec.toNat_setWidth, BitVec.toNat_ofNat, Nat.mod_eq_of_lt ha,
    Nat.mod_eq_of_lt hav]

theorem inIvs_ofNat {w v : Nat} {ivs : List (Nat × Nat)} (hiv : ∀ iv ∈ ivs, iv.1 < 2 ^ w ∧ iv.2 < 2 ^ w)
    (hv : v < 2 ^ w) : inIvs ivs (BitVec.ofNat w v) = inNat ivs v := by
  induction ivs with
  | nil => rfl
  | cons iv ivs ih =>
    have h1 := hiv iv (by simp)
    simp only [inIvs, inNat, List.any_cons] at ih ⊢
    rw [ih (fun j hj => hiv j (by simp [hj])), ule_ofNat h1.1 hv, ule_ofNat hv h1.2]

/-! Bound lists of distinct positions below `m` -/

theorem prod_le_range (f : Nat → Nat) (hf : ∀ i, 1 ≤ f i) :
    ∀ (m : Nat) (l : List Nat), l.Nodup → (∀ i ∈ l, i < m) → (l.map f).prod ≤ ((List.range m).map f).prod := by
  intro m
  induction m with
  | zero =>
    intro l _ hl
    cases l with
    | nil => simp
    | cons i l => exact absurd (hl i (by simp)) (by omega)
  | succ m ih =>
    intro l hnd hl
    rw [List.range_succ, List.map_append, prod_append']
    simp only [List.map_cons, List.map_nil, List.prod_cons, List.prod_nil, Nat.mul_one]
    by_cases hm : m ∈ l
    · have hp := (List.perm_cons_erase hm).map f
      rw [hp.prod_nat, List.map_cons, List.prod_cons]
      have hlt : ∀ i ∈ l.erase m, i < m := by
        intro i hi
        have := (List.Nodup.mem_erase_iff hnd).mp hi
        have := hl i this.2
        omega
      have := ih (l.erase m) (hnd.erase m) hlt
      rw [Nat.mul_comm]
      exact Nat.mul_le_mul_right _ this
    · have hlt : ∀ i ∈ l, i < m := by
        intro i hi
        have := hl i hi
        have : i ≠ m := fun h => hm (h ▸ hi)
        omega
      exact Nat.le_trans (ih l hnd hlt) (Nat.le_mul_of_pos_right _ (hf m))

theorem length_le_range : ∀ (m : Nat) (l : List Nat), l.Nodup → (∀ i ∈ l, i < m) → l.length ≤ m := by
  intro m
  induction m with
  | zero =>
    intro l _ hl
    cases l with
    | nil => simp
    | cons i l => exact absurd (hl i (by simp)) (by omega)
  | succ m ih =>
    intro l hnd hl
    by_cases hm : m ∈ l
    · have hp := List.perm_cons_erase hm
      rw [hp.length_eq, List.length_cons]
      have hlt : ∀ i ∈ l.erase m, i < m := by
        intro i hi
        have := (List.Nodup.mem_erase_iff hnd).mp hi
        have := hl i this.2
        omega
      have := ih (l.erase m) (hnd.erase m) hlt
      omega
    · have hlt : ∀ i ∈ l, i < m := by
        intro i hi
        have := hl i hi
        have : i ≠ m := fun h => hm (h ▸ hi)
        omega
      have := ih l hnd hlt
      omega

/-! Turn a natural-number program into an assignment of the encoding's variables -/

/-- Mark multiplication and division as the multiplicative pair -/
def opM : Op → Bool
  | .mul => true
  | .div => true
  | _ => false

/-- Mark subtraction and division as the inverse operations -/
def opI : Op → Bool
  | .sub => true
  | .div => true
  | _ => false

/-- Encode one natural-number step as an active step -/
def toStep (w : Nat) (s : NStep) : Step w :=
  ⟨true, sel s.a, sel s.b, opM s.op, opI s.op, BitVec.ofNat w s.va, BitVec.ofNat w s.vb, BitVec.ofNat w s.v⟩

/-- Assign step `k` of a program, idle beyond its end -/
def asg (w : Nat) (S : List NStep) (k : Nat) : Step w := (S[k]?.map (toStep w)).getD (Step.idle w)

theorem asg_of_lt {w : Nat} {S : List NStep} {k : Nat} {s : NStep} (h : S[k]? = some s) :
    asg w S k = toStep w s := by
  simp [asg, h]

theorem act_asg (w : Nat) (S : List NStep) (k : Nat) : (asg w S k).act = decide (k < S.length) := by
  unfold asg
  by_cases hk : k < S.length
  · rw [List.getElem?_eq_getElem hk]; simp [toStep, hk]
  · rw [List.getElem?_eq_none (by omega)]; simp [Step.idle, hk]

theorem pick_asg {w : Nat} {S : List NStep} (hS : S.length ≤ 5) :
    pick [asg w S 0, asg w S 1, asg w S 2, asg w S 3, asg w S 4] = asg w S := by
  funext k
  match k with
  | 0 | 1 | 2 | 3 | 4 => rfl
  | k + 5 =>
    simp only [pick, List.getD_cons_succ, List.getD_nil, asg]
    rw [List.getElem?_eq_none (by omega)]
    rfl

/-- Show that an assignment built from a program with the compiled invariants satisfies the encoding -/
theorem enc_asg {p : List Nat} {ivs : List (Nat × Nat)} {w B : Nat} {S : List NStep}
    (hB : B ≤ 2 ^ w) (hiv : ∀ iv ∈ ivs, iv.1 < 2 ^ w ∧ iv.2 < 2 ^ w)
    (hn1 : 1 ≤ S.length) (hn5 : S.length ≤ 5)
    (hinv : ∀ k s, S[k]? = some s → StepInv p 6 S B k s)
    (hnd : (ops S).Nodup)
    (hused : ∀ k, k + 1 < S.length → 6 + k ∈ ops S)
    (hclean : ∀ k s, S[k]? = some s → k + 1 < S.length → inNat ivs s.v = false)
    (hlast : ∀ s, S[S.length - 1]? = some s → inNat ivs s.v = true) :
    Enc p ivs w (asg w S) = true := by
  have hw1 : 1 ≤ 2 ^ w := Nat.one_le_two_pow
  -- Read the facts about a step as in-range numbers
  have hget : ∀ k, k < S.length → ∃ s, S[k]? = some s := fun k hk => ⟨S[k], List.getElem?_eq_getElem hk⟩
  have hreg : ∀ k s, S[k]? = some s → s.a < 6 + k ∧ s.b < 6 + k := by
    intro k s hs
    obtain ⟨h1, h2, -⟩ := hinv k s hs
    constructor
    · rcases h1 with ⟨h, -⟩ | ⟨m, h, hm, -⟩ <;> omega
    · rcases h2 with ⟨h, -⟩ | ⟨m, h, hm, -⟩ <;> omega
  have hlen : ∀ k s, S[k]? = some s → k < S.length := fun k s hs => (List.getElem?_eq_some_iff.mp hs).1
  have hops : ∀ i, i < 2 * S.length → ∃ s, S[i / 2]? = some s ∧
      (ops S)[i]? = some (if i % 2 = 0 then s.a else s.b) := by
    intro i hi
    obtain ⟨j, hj⟩ : ∃ j, i = 2 * j ∨ i = 2 * j + 1 := ⟨i / 2, by omega⟩
    rcases hj with rfl | rfl
    · obtain ⟨s, hs⟩ := hget j (by omega)
      have e : 2 * j / 2 = j := by omega
      refine ⟨s, by rw [e]; exact hs, ?_⟩
      rw [ops_getElem?_even, hs]; simp
    · obtain ⟨s, hs⟩ := hget j (by omega)
      have e : (2 * j + 1) / 2 = j := by omega
      have e2 : (2 * j + 1) % 2 = 1 := by omega
      refine ⟨s, by rw [e]; exact hs, ?_⟩
      rw [ops_getElem?_odd, hs, e2]; simp
  -- Settle the slot reading of an active step
  have hslot : ∀ i s, S[i / 2]? = some s →
      slot (asg w S) i = sel (if i % 2 = 0 then s.a else s.b) := by
    intro i s hs
    unfold slot
    rw [asg_of_lt hs]
    split <;> simp [toStep, *]
  unfold Enc
  simp only [Bool.and_eq_true, ball_iff]
  refine ⟨⟨⟨⟨⟨?c0, ?c1⟩, ?c2⟩, ?c3⟩, ?c4⟩, ?c5⟩
  · -- Make the first step active
    rw [act_asg]; simp; omega
  · -- Keep the active steps a prefix
    intro k _
    simp only [act_asg, Bool.or_eq_true, Bool.not_eq_true', decide_eq_false_iff_not, decide_eq_true_eq]
    omega
  · -- Check each active step
    intro k _
    simp only [act_asg, Bool.or_eq_true, Bool.not_eq_true', decide_eq_false_iff_not]
    by_cases hk : k < S.length
    · right
      obtain ⟨s, hs⟩ := hget k hk
      obtain ⟨hA, hB', hpo, ⟨hv0, hva, hvb, hcomm, hsem⟩, hbv, hba, hbb⟩ := hinv k s hs
      have hv : s.v < 2 ^ w := by omega
      have ha : s.va < 2 ^ w := by omega
      have hb : s.vb < 2 ^ w := by omega
      have hab := hreg k s hs
      have hk5 : k < 5 := by omega
      -- Show that the two operand registers of a step differ
      have hne : s.a ≠ s.b := by
        have h0 := hops (2 * k) (by omega)
        have h1 := hops (2 * k + 1) (by omega)
        obtain ⟨s0, hs0, h0⟩ := h0
        obtain ⟨s1, hs1, h1⟩ := h1
        have e0 : 2 * k / 2 = k := by omega
        have e1 : (2 * k + 1) / 2 = k := by omega
        rw [e0, hs] at hs0
        rw [e1, hs] at hs1
        cases hs0; cases hs1
        simp at h0 h1
        intro heq
        rw [heq] at h0
        have := (List.Nodup.getElem?_inj (by rw [length_ops]; omega) hnd).mp (h0.trans h1.symm)
        omega
      unfold stepOK
      rw [asg_of_lt hs]
      simp only [toStep, Bool.and_eq_true, and_assoc]
      refine ⟨?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_⟩
      · rw [ult_ofNat (by omega) (by omega)]; simp; omega
      · rw [ult_ofNat (by omega) (by omega)]; simp; omega
      · rw [ball_iff]
        intro j hj
        simp only [Bool.and_eq_true, Bool.or_eq_true, bne_iff_ne, ne_eq, beq_iff_eq]
        -- Read a register that an operand selects
        have hread : ∀ x vx, x < 6 + k → RegOK p 6 S k x vx →
            (¬ sel x = sel j ∨ BitVec.ofNat w vx = reg p (asg w S) j) := by
          intro x vx hx hR
          by_cases hxj : sel x = sel j
          · right
            have hxj' : x = j := ofNat_inj (by omega) (by omega) hxj
            subst hxj'
            unfold reg
            rcases hR with ⟨h6, hval⟩ | ⟨m, hm, hmk, hval⟩
            · simp only [h6, ↓reduceIte, hval]
            · have h6 : ¬ x < 6 := by omega
              simp only [h6, ↓reduceIte]
              obtain ⟨sm, hsm⟩ := hget m (by omega)
              rw [hsm] at hval
              simp at hval
              have : x - 6 = m := by omega
              rw [this, asg_of_lt hsm]
              simp [toStep, hval]
          · exact Or.inl hxj
        exact ⟨hread _ _ hab.1 hA, hread _ _ hab.2 hB'⟩
      · simp only [bne_iff_ne, ne_eq]
        intro h
        have := ofNat_inj hv (by omega) (h.trans (BitVec.ofNat_eq_ofNat (n := w) (i := 0)))
        omega
      · -- Check the additive pair
        simp only [Bool.or_eq_true, beq_iff_eq]
        cases hop : s.op <;> simp only [hop, opM, opI] at hsem ⊢ <;> simp
        · rw [zext_ofNat hb (by omega), zext_ofNat ha (by omega), zext_ofNat hv (by omega),
            ← BitVec.ofNat_add, hsem]
        · rw [zext_ofNat hb (by omega), zext_ofNat ha (by omega), zext_ofNat hv (by omega),
            ← BitVec.ofNat_add, hsem]
      · -- Check the multiplicative pair
        simp only [Bool.or_eq_true, beq_iff_eq, Bool.not_eq_true']
        cases hop : s.op <;> simp only [hop, opM, opI] at hsem ⊢ <;> simp
        · rw [zext_ofNat hb (by omega), zext_ofNat ha (by omega), zext_ofNat hv (by omega),
            ← BitVec.ofNat_mul, hsem]
        · rw [zext_ofNat hb (by omega), zext_ofNat ha (by omega), zext_ofNat hv (by omega),
            ← BitVec.ofNat_mul, hsem]
      · -- Order the operands of a commutative operation
        simp only [Bool.or_eq_true]
        cases hop : s.op <;> simp only [hop, opI, opComm] at hcomm ⊢ <;> simp
        · rw [ult_ofNat (by omega) (by omega)]; simp; have := hcomm trivial; omega
        · rw [ult_ofNat (by omega) (by omega)]; simp; have := hcomm trivial; omega
      · exact bne_ofNat hv ha hva
      · exact bne_ofNat hv hb hvb
      · -- Check the post-order condition
        simp only [Bool.or_eq_true, beq_iff_eq, Bool.and_eq_true]
        by_cases h0 : k = 0
        · left; left; left; exact h0
        · by_cases h6 : 6 ≤ s.a ∨ 6 ≤ s.b
          · rcases hpo h6 with h | h
            · left; right; congr 1; omega
            · right; congr 1; omega
          · left; left; right
            rw [ult_ofNat (by omega) (by omega), ult_ofNat (by omega) (by omega)]
            simp; omega
      · -- Keep target values out of every step but the last
        simp only [Bool.or_eq_true, Bool.not_eq_true', act_asg, decide_eq_false_iff_not]
        by_cases hk1 : k + 1 < S.length
        · right
          rw [inIvs_ofNat hiv hv]
          exact hclean k s hs hk1
        · left; exact hk1
    · left; exact hk
  · -- Put the last result in the intervals
    intro k _
    simp only [act_asg]
    by_cases hk : k < S.length ∧ ¬ k + 1 < S.length
    · obtain ⟨s, hs⟩ := hget k hk.1
      have hkl : k = S.length - 1 := by omega
      rw [asg_of_lt hs]
      obtain ⟨-, -, -, -, hbv, -, -⟩ := hinv k s hs
      simp only [toStep]
      rw [inIvs_ofNat hiv (by omega), hlast s (hkl ▸ hs)]
      simp
    · rcases (by omega : ¬ k < S.length ∨ k + 1 < S.length) with h | h <;> simp [h]
  · -- Feed every result but the last to a later step
    intro k hk4
    simp only [act_asg, Bool.or_eq_true, Bool.not_eq_true', decide_eq_false_iff_not, bany_iff,
      Bool.and_eq_true, decide_eq_true_eq, beq_iff_eq]
    by_cases hk : k + 1 < S.length
    · right
      obtain ⟨i, hi⟩ := List.mem_iff_getElem?.mp (hused k hk)
      have hi2 : i < 2 * S.length := by
        have := (List.getElem?_eq_some_iff.mp hi).1
        rw [length_ops] at this; exact this
      obtain ⟨s, hs, hsi⟩ := hops i hi2
      rw [hi] at hsi
      have hreg' := hreg (i / 2) s hs
      have hlt : i / 2 < S.length := hlen _ _ hs
      have hx : 6 + k = (if i % 2 = 0 then s.a else s.b) := by simpa using hsi
      -- Show that the consuming step comes after step k
      have hgt : k < i / 2 := by split at hx <;> omega
      refine ⟨i / 2 - k - 1, by omega, ?_⟩
      have he : k + 1 + (i / 2 - k - 1) = i / 2 := by omega
      rw [he]
      refine ⟨hlt, ?_⟩
      rw [asg_of_lt hs]
      simp only [toStep]
      split at hx
      · left; rw [hx]
      · right; rw [hx]
    · left; exact hk
  · -- Use each register at most once
    intro i hi d hd
    simp only [act_asg, Bool.or_eq_true, Bool.not_eq_true', decide_eq_false_iff_not, bne_iff_ne, ne_eq]
    by_cases hj : (i + 1 + d) / 2 < S.length
    · right
      obtain ⟨s, hs, hsi⟩ := hops i (by omega)
      obtain ⟨s', hs', hsj⟩ := hops (i + 1 + d) (by omega)
      rw [hslot i s hs, hslot (i + 1 + d) s' hs']
      have h1 := hreg (i / 2) s hs
      have h2 := hreg _ s' hs'
      have hl1 := hlen _ _ hs
      have hl2 := hlen _ _ hs'
      intro heq
      have hx : (if i % 2 = 0 then s.a else s.b) = (if (i + 1 + d) % 2 = 0 then s'.a else s'.b) := by
        apply ofNat_inj (w := 4) (by split <;> omega) (by split <;> omega) heq
      rw [← hx] at hsj
      have := (List.Nodup.getElem?_inj (by rw [length_ops]; omega) hnd).mp (hsi.trans hsj.symm)
      omega
    · left; exact hj

/-- Show that a solvable target in the intervals gives a satisfying assignment of the encoding -/
theorem enc_complete {p : List Nat} {ivs : List (Nat × Nat)} {w : Nat}
    (hlen : p.length = 6)
    (hw : ((List.range 6).map fun i => p.getD i 0 + 1).prod ≤ 2 ^ w)
    (hiv : ∀ iv ∈ ivs, iv.1 < 2 ^ w ∧ iv.2 < 2 ^ w)
    (hleaf : ∀ v ∈ p, inNat ivs v = false)
    {t : Nat} (ht : inNat ivs t = true) (hsol : Solvable p t) :
    ∃ s0 s1 s2 s3 s4 : Step w, Enc p ivs w (pick [s0, s1, s2, s3, s4]) = true := by
  obtain ⟨e, hlegal, he⟩ := hsol
  -- Prune to a tight expression and take its first subexpression in the set
  obtain ⟨hp1, hp2, hp3⟩ := prune_spec he
  have hhit : hit p (inNat ivs) (prune p e) = true := by simp [hit, hp1, ht]
  obtain ⟨x, hx⟩ := find_isSome hhit
  obtain ⟨hxhit, hxkids, hxsub, hxtight⟩ := find_some hx hp3
  have hxlegal : x.leaves.Nodup := hlegal.sublist (hxsub.trans hp2)
  obtain ⟨v, hxv, hvin⟩ : ∃ v, x.eval p = some v ∧ inNat ivs v = true := by
    unfold hit at hxhit
    split at hxhit
    · exact ⟨_, by assumption, hxhit⟩
    · cases hxhit
  have hxl6 : ∀ i ∈ x.leaves, i < 6 := fun i hi => hlen ▸ leaves_lt_of_eval hxv i hi
  cases x with
  | leaf i =>
    -- Rule out a pool number in the set
    obtain ⟨hi, _⟩ := eval_leaf.mp hxv
    have := hleaf v (List.mem_of_getElem? hi)
    rw [this] at hvin; cases hvin
  | node op l r =>
    -- Compile the node and check the invariants that `enc_asg` needs
    obtain ⟨hcl, hcr⟩ := hxkids
    obtain ⟨a, b, ha, hb, _, _⟩ := eval_node.mp hxv
    have hperm := compile_perm (p := p) (Expr.node op l r) 6
    have hlenS := compile_node_len (p := p) op l r 6
    have hroot := compile_node_root (p := p) op l r 6
    generalize hS : (compile p (Expr.node op l r) 6) = C at hperm hlenS hroot
    have hnd : (Expr.node op l r).leaves ++ List.range' 6 C.2.2.length |>.Nodup := by
      rw [List.nodup_append]
      refine ⟨hxlegal, List.nodup_range' .., ?_⟩
      intro u hu u' hu'
      have := hxl6 u hu
      rw [List.mem_range'] at hu'
      omega
    have hnd' := hperm.nodup_iff.mpr hnd
    have hcount := hperm.length_eq
    simp only [List.length_append, length_ops, List.length_cons, List.length_nil, List.length_range'] at hcount
    have hl6 := length_le_range 6 _ hxlegal hxl6
    have hn5 : C.2.2.length ≤ 5 := by omega
    have hn1 : 1 ≤ C.2.2.length := by omega
    refine ⟨asg w C.2.2 0, asg w C.2.2 1, asg w C.2.2 2, asg w C.2.2 3, asg w C.2.2 4, ?_⟩
    rw [pick_asg hn5]
    have hbound : prodL p (Expr.node op l r).leaves ≤ 2 ^ w :=
      Nat.le_trans (prod_le_range _ (fun _ => by omega) 6 _ hxlegal hxl6) hw
    apply enc_asg hbound hiv hn1 hn5
    · intro k s hs
      have := compile_inv (p := p) 6 hxv hxtight hxl6 k s (by rw [hS]; exact hs)
      rw [hS] at this; exact this
    · exact (List.nodup_append.mp hnd').1
    · intro k hk
      have hmem : 6 + k ∈ (Expr.node op l r).leaves ++ List.range' 6 C.2.2.length := by
        rw [List.mem_append]; right; rw [List.mem_range']; exact ⟨k, by omega, by omega⟩
      have := hperm.mem_iff.mpr hmem
      simp only [List.mem_append, List.mem_singleton] at this
      rcases this with h | h
      · exact h
      · omega
    · -- Steps before the last come from the clean children
      intro k s hs hk
      have hlen0 := compile_node_len (p := p) op l r 6
      rw [hS] at hlen0
      have hS' := hS
      simp only [compile] at hS'
      rw [← hS'] at hs
      simp only at hs
      rw [List.getElem?_append_left (by simp; omega)] at hs
      have hmem := List.mem_of_getElem? hs
      rw [List.mem_append] at hmem
      rcases hmem with h | h
      · exact compile_clean 6 ha hcl s h
      · exact compile_clean _ hb hcr s h
    · intro s hs
      have hlast := compile_node_last (p := p) op l r 6
      rw [hS, hs] at hlast
      have hval := compile_val (p := p) 6 hxv
      rw [hS] at hval
      simp at hlast
      rw [hlast, hval]; exact hvin

/-- Conclude from an unsatisfiable encoding that no target in the intervals has an exact solution -/
theorem not_solvable_of_unsat {p : List Nat} {ivs : List (Nat × Nat)} {w : Nat}
    (hlen : p.length = 6)
    (hw : ((List.range 6).map fun i => p.getD i 0 + 1).prod ≤ 2 ^ w)
    (hiv : ∀ iv ∈ ivs, iv.1 < 2 ^ w ∧ iv.2 < 2 ^ w)
    (hleaf : ∀ v ∈ p, inNat ivs v = false)
    (hunsat : ∀ s0 s1 s2 s3 s4 : Step w, Enc p ivs w (pick [s0, s1, s2, s3, s4]) = false)
    {t : Nat} (ht : inNat ivs t = true) : ¬ Solvable p t := by
  intro hsol
  obtain ⟨s0, s1, s2, s3, s4, h⟩ := enc_complete hlen hw hiv hleaf ht hsol
  rw [hunsat] at h
  cases h

end Countdown.Sat
