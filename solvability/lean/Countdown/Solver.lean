import Countdown.Expr

/-! Decide solvability by tabulating the reachable values of every mask with structural recursion, so the kernel can run it too and only membership matters for correctness -/

namespace Countdown

/-! Represent finite sets as lists kept ascending and duplicate-free by merging -/

/-- Merge two ascending lists into an ascending list without repeats, falling back to concatenation when fuel runs out -/
def merge : Nat → List Nat → List Nat → List Nat → List Nat
  | 0, xs, ys, acc => acc.reverseAux (xs ++ ys)
  | _ + 1, [], ys, acc => acc.reverseAux ys
  | _ + 1, x :: xs, [], acc => acc.reverseAux (x :: xs)
  | f + 1, x :: xs, y :: ys, acc =>
    if x < y then merge f xs (y :: ys) (x :: acc)
    else if y < x then merge f (x :: xs) ys (y :: acc)
    else merge f xs ys (x :: acc)

theorem mem_merge (f : Nat) (xs ys acc : List Nat) (v : Nat) :
    v ∈ merge f xs ys acc ↔ v ∈ xs ∨ v ∈ ys ∨ v ∈ acc := by
  induction f generalizing xs ys acc with
  | zero => simp [merge]; grind
  | succ f ih =>
    match xs, ys with
    | [], ys => simp [merge]; grind
    | x :: xs, [] => simp [merge]; grind
    | x :: xs, y :: ys =>
      simp only [merge]
      split
      · rw [ih]; simp; grind
      · split
        · rw [ih]; simp; grind
        · rw [ih]; simp
          have : x = y := by omega
          subst this; grind

/-- Take the union of two sets -/
def union (xs ys : List Nat) : List Nat := merge (xs.length + ys.length) xs ys []

theorem mem_union {xs ys : List Nat} {v : Nat} : v ∈ union xs ys ↔ v ∈ xs ∨ v ∈ ys := by
  simp [union, mem_merge]

/-- Merge neighbouring lists pairwise -/
def mergePairs : List (List Nat) → List (List Nat)
  | a :: b :: rest => union a b :: mergePairs rest
  | ls => ls

theorem mem_mergePairs (ls : List (List Nat)) (v : Nat) :
    (∃ l ∈ mergePairs ls, v ∈ l) ↔ ∃ l ∈ ls, v ∈ l := by
  induction ls using mergePairs.induct with
  | case1 a b rest ih =>
    simp only [mergePairs, List.mem_cons, exists_eq_or_imp, mem_union, ih]
    grind
  | case2 ls h =>
    rw [mergePairs.eq_2 _ h]

/-- Merge a list of sets in rounds until one remains, flattening if fuel runs out -/
def mergeAll : Nat → List (List Nat) → List Nat
  | _, [] => []
  | _, [a] => a
  | 0, ls => ls.flatten
  | f + 1, ls => mergeAll f (mergePairs ls)

theorem mem_mergeAll (f : Nat) (ls : List (List Nat)) (v : Nat) :
    v ∈ mergeAll f ls ↔ ∃ l ∈ ls, v ∈ l := by
  induction f generalizing ls with
  | zero =>
    match ls with
    | [] => simp [mergeAll]
    | [a] => simp [mergeAll]
    | a :: b :: rest => simp [mergeAll]
  | succ f ih =>
    match ls with
    | [] => simp [mergeAll]
    | [a] => simp [mergeAll]
    | a :: b :: rest => simp only [mergeAll]; rw [ih, mem_mergePairs]

/-- Sort a list and remove repeats by bottom-up merging -/
def norm (l : List Nat) : List Nat := mergeAll l.length (l.map fun x => [x])

theorem mem_norm {l : List Nat} {v : Nat} : v ∈ norm l ↔ v ∈ l := by
  simp only [norm, mem_mergeAll, List.mem_map]
  constructor
  · rintro ⟨_, ⟨a, ha, rfl⟩, hv⟩
    simp at hv; subst hv; exact ha
  · intro hv
    exact ⟨[v], ⟨v, hv, rfl⟩, by simp⟩

/-! Compute the reachable values one subset at a time -/

/-- List every value one legal operation can make from two values in either order -/
def results (a b : Nat) : List Nat :=
  [Op.add, Op.sub, Op.mul, Op.div].flatMap fun op =>
    ((op.apply a b).bind pos).toList ++ ((op.apply b a).bind pos).toList

theorem mem_results {a b v : Nat} :
    v ∈ results a b ↔ ∃ op : Op, (op.apply a b).bind pos = some v ∨ (op.apply b a).bind pos = some v := by
  simp only [results, List.mem_flatMap, List.mem_append, Option.mem_toList]
  constructor
  · rintro ⟨op, _, h⟩
    exact ⟨op, by simpa [eq_comm] using h⟩
  · rintro ⟨op, h⟩
    exact ⟨op, by cases op <;> simp, by simpa [eq_comm] using h⟩

theorem pos_eq_some {x v : Nat} : pos x = some v ↔ 0 < x ∧ x = v := by
  unfold pos; split <;> simp_all

theorem results_comm {a b v : Nat} : v ∈ results a b ↔ v ∈ results b a := by
  simp only [mem_results]
  exact ⟨fun ⟨op, h⟩ => ⟨op, h.symm⟩, fun ⟨op, h⟩ => ⟨op, h.symm⟩⟩

theorem mem_results_pos {a b v : Nat} (ha : 0 < a) (hb : 0 < b) :
    v ∈ results a b ↔ v = a + b ∨ v = a * b ∨ (b < a ∧ v = a - b) ∨ (a < b ∧ v = b - a) ∨
      (b ∣ a ∧ v = a / b) ∨ (a ∣ b ∧ v = b / a) := by
  have hab : b ∣ a → 0 < a / b := fun h => Nat.div_pos (Nat.le_of_dvd ha h) hb
  have hba : a ∣ b → 0 < b / a := fun h => Nat.div_pos (Nat.le_of_dvd hb h) ha
  rw [mem_results]
  constructor
  · rintro ⟨op, h | h⟩ <;> cases op <;> simp only [Op.apply] at h <;>
      (repeat' split at h) <;> (try simp only [reduceCtorEq, Option.bind_some, Option.bind_none] at h) <;>
      (try rw [pos_eq_some] at h) <;> (try obtain ⟨_, rfl⟩ := h) <;>
      first | omega | simp_all [Nat.mul_comm] | simp_all [Nat.add_comm]
  · rintro (h | h | ⟨h1, h⟩ | ⟨h1, h⟩ | ⟨h1, h⟩ | ⟨h1, h⟩) <;> subst h
    · exact ⟨.add, Or.inl (by simp [Op.apply, pos]; omega)⟩
    · exact ⟨.mul, Or.inl (by simp [Op.apply, pos, Nat.mul_pos ha hb])⟩
    · exact ⟨.sub, Or.inl (by simp [Op.apply, pos, h1]; omega)⟩
    · exact ⟨.sub, Or.inr (by simp [Op.apply, pos, h1]; omega)⟩
    · exact ⟨.div, Or.inl (by simp [Op.apply, pos, h1, hb, hab h1])⟩
    · exact ⟨.div, Or.inr (by simp [Op.apply, pos, h1, ha, hba h1])⟩

/-- List the ascending runs of values that `a` makes with the elements of an ascending list `B` -/
def runs (a : Nat) (B : List Nat) : List (List Nat) :=
  [B.map (a + ·), B.map (a * ·),
   (B.filterMap fun b => if b < a then some (a - b) else none).reverse,
   B.filterMap (fun b => if a < b then some (b - a) else none),
   (B.filterMap fun b => if b ∣ a then some (a / b) else none).reverse,
   B.filterMap (fun b => if a ∣ b then some (b / a) else none)]

theorem mem_runs {a v : Nat} {B : List Nat} (ha : 0 < a) (hB : ∀ b ∈ B, 0 < b) :
    (∃ l ∈ runs a B, v ∈ l) ↔ ∃ b ∈ B, v ∈ results a b := by
  simp only [runs, List.mem_cons, List.not_mem_nil, or_false, exists_eq_or_imp, exists_eq_left,
    List.mem_map, List.mem_reverse, List.mem_filterMap]
  constructor
  · rintro (⟨b, hb, h⟩ | ⟨b, hb, h⟩ | ⟨b, hb, h⟩ | ⟨b, hb, h⟩ | ⟨b, hb, h⟩ | ⟨b, hb, h⟩) <;>
      refine ⟨b, hb, (mem_results_pos ha (hB b hb)).mpr ?_⟩ <;>
      (try split at h) <;> (try simp only [Option.some.injEq, reduceCtorEq] at h) <;> subst h <;> simp_all
  · rintro ⟨b, hb, h⟩
    rcases (mem_results_pos ha (hB b hb)).mp h with h | h | ⟨h1, h⟩ | ⟨h1, h⟩ | ⟨h1, h⟩ | ⟨h1, h⟩ <;>
      subst h
    · exact Or.inl ⟨b, hb, rfl⟩
    · exact Or.inr (Or.inl ⟨b, hb, rfl⟩)
    · exact Or.inr (Or.inr (Or.inl ⟨b, hb, by simp [h1]⟩))
    · exact Or.inr (Or.inr (Or.inr (Or.inl ⟨b, hb, by simp [h1]⟩)))
    · exact Or.inr (Or.inr (Or.inr (Or.inr (Or.inl ⟨b, hb, by simp [h1]⟩))))
    · exact Or.inr (Or.inr (Or.inr (Or.inr (Or.inr ⟨b, hb, by simp [h1]⟩))))

/-- Combine every value of one set with every value of another as ascending runs, looping over the smaller set -/
def pairs (A B : List Nat) : List (List Nat) :=
  if A.length ≤ B.length then A.flatMap (runs · B) else B.flatMap (runs · A)

theorem mem_pairs {A B : List Nat} {v : Nat} (hA : ∀ a ∈ A, 0 < a) (hB : ∀ b ∈ B, 0 < b) :
    (∃ l ∈ pairs A B, v ∈ l) ↔ ∃ a ∈ A, ∃ b ∈ B, v ∈ results a b := by
  unfold pairs
  split
  · simp only [List.mem_flatMap]
    constructor
    · rintro ⟨l, ⟨a, ha, hl⟩, hv⟩
      exact ⟨a, ha, (mem_runs (hA a ha) hB).mp ⟨l, hl, hv⟩⟩
    · rintro ⟨a, ha, h⟩
      obtain ⟨l, hl, hv⟩ := (mem_runs (hA a ha) hB).mpr h
      exact ⟨l, ⟨a, ha, hl⟩, hv⟩
  · simp only [List.mem_flatMap]
    constructor
    · rintro ⟨l, ⟨b, hb, hl⟩, hv⟩
      obtain ⟨a, ha, h⟩ := (mem_runs (hB b hb) hA).mp ⟨l, hl, hv⟩
      exact ⟨a, ha, b, hb, results_comm.mp h⟩
    · rintro ⟨a, ha, b, hb, h⟩
      obtain ⟨l, hl, hv⟩ := (mem_runs (hB b hb) hA).mpr ⟨a, ha, results_comm.mp h⟩
      exact ⟨l, ⟨b, hb, hl⟩, hv⟩

/-- List the value of the single leaf whose mask is `m`, if there is one -/
def leafVals (p : List Nat) (m : Nat) : List Nat :=
  (List.range p.length).filterMap fun i => if 2 ^ i = m then p[i]?.bind pos else none

/-- Combine the tables of the two halves of every split of `m`, each unordered split once -/
def splitVals (T : List (List Nat)) (m : Nat) : List (List Nat) :=
  (List.range m).flatMap fun s =>
    if s ≠ 0 ∧ s &&& m = s ∧ s < m ^^^ s then pairs (T.getD s []) (T.getD (m ^^^ s) []) else []

/-- Compute the reachable set of mask `m` from the table of all smaller masks -/
def entry (p : List Nat) (T : List (List Nat)) (m : Nat) : List Nat :=
  let runs := leafVals p m :: splitVals T m
  mergeAll runs.length runs

/-- Tabulate the reachable sets of masks `0` to `k` -/
def buildTable (p : List Nat) : Nat → List (List Nat)
  | 0 => [[]]
  | k + 1 => let T := buildTable p k; T ++ [entry p T (k + 1)]

/-- Tabulate the reachable set of every mask of the pool -/
def table (p : List Nat) : List (List Nat) := buildTable p (2 ^ p.length - 1)

/-- Collect every value reachable from any non-empty set of positions -/
def reachable (p : List Nat) : List Nat :=
  let sets := (table p).drop 1
  mergeAll sets.length sets

/-- Decide whether a target is reachable -/
def solvableB (p : List Nat) (t : Nat) : Bool := (reachable p).contains t

/-! Prove the table sound and complete -/

/-- State that some legal expression with leaf mask exactly `m` evaluates to `v` -/
def ReachM (p : List Nat) (m v : Nat) : Prop :=
  ∃ e : Expr, e.Legal ∧ e.mask = m ∧ e.eval p = some v

theorem length_buildTable (p : List Nat) (k : Nat) : (buildTable p k).length = k + 1 := by
  induction k with
  | zero => rfl
  | succ k ih => simp [buildTable, ih]

theorem getD_buildTable (p : List Nat) {s k : Nat} (h : s ≤ k) :
    (buildTable p k).getD s [] = (buildTable p s).getD s [] := by
  induction k with
  | zero => have : s = 0 := by omega
            subst this; rfl
  | succ k ih =>
    rcases Nat.lt_or_eq_of_le h with h | h
    · rw [← ih (by omega)]
      simp only [buildTable, List.getD_eq_getElem?_getD]
      rw [List.getElem?_append_left (by rw [length_buildTable]; omega)]
    · subst h; rfl

theorem getD_buildTable_succ (p : List Nat) (k : Nat) :
    (buildTable p (k + 1)).getD (k + 1) [] = entry p (buildTable p k) (k + 1) := by
  simp only [buildTable, List.getD_eq_getElem?_getD]
  rw [List.getElem?_append_right (by rw [length_buildTable]; omega)]
  simp [length_buildTable]

theorem le_of_and_eq {s m : Nat} (h : s &&& m = s) : s ≤ m := h ▸ Nat.and_le_right

theorem testBit_of_and_eq {s m i : Nat} (h : s &&& m = s) (hi : s.testBit i = true) : m.testBit i = true := by
  have := congrArg (fun n => n.testBit i) h
  simp only [Nat.testBit_and, hi] at this
  simpa using this

/-- Split a mask into a submask and its complement -/
theorem split_facts {s m : Nat} (h : s &&& m = s) :
    (m ^^^ s) &&& m = m ^^^ s ∧ s &&& (m ^^^ s) = 0 ∧ s ||| (m ^^^ s) = m ∧ m ^^^ (m ^^^ s) = s := by
  have hb : ∀ i, s.testBit i = true → m.testBit i = true := fun i => testBit_of_and_eq h
  refine ⟨?_, ?_, ?_, ?_⟩ <;> apply Nat.eq_of_testBit_eq <;> intro i <;> have := hb i <;>
    simp only [Nat.testBit_and, Nat.testBit_xor, Nat.testBit_or, Nat.zero_testBit] <;>
    cases hs : s.testBit i <;> cases hm : m.testBit i <;> simp_all

/-- Recover the split data of a node from its children's masks -/
theorem node_facts {a b : Nat} (h : a &&& b = 0) :
    a &&& (a ||| b) = a ∧ (a ||| b) ^^^ a = b := by
  have hd := (Expr.and_eq_zero_iff a b).mp h
  refine ⟨?_, ?_⟩ <;> apply Nat.eq_of_testBit_eq <;> intro i <;> have := hd i <;>
    simp only [Nat.testBit_and, Nat.testBit_xor, Nat.testBit_or] <;>
    cases hs : a.testBit i <;> cases hm : b.testBit i <;> simp_all

theorem lt_of_proper {s m : Nat} (h : s &&& m = s) (hne : ∃ i, m.testBit i = true ∧ s.testBit i = false) :
    s < m := by
  rcases Nat.lt_or_eq_of_le (le_of_and_eq h) with h | h
  · exact h
  · subst h; obtain ⟨i, h1, h2⟩ := hne; simp_all

theorem or_comm' (a b : Nat) : a ||| b = b ||| a := by
  apply Nat.eq_of_testBit_eq; intro i; simp [Bool.or_comm]

theorem mem_leafVals {p : List Nat} {m v : Nat} :
    v ∈ leafVals p m ↔ ∃ i, 2 ^ i = m ∧ (Expr.leaf i).eval p = some v := by
  simp only [leafVals, List.mem_filterMap, List.mem_range]
  constructor
  · rintro ⟨i, _, h⟩
    split at h
    · exact ⟨i, by assumption, by simpa [Expr.eval] using h⟩
    · simp at h
  · rintro ⟨i, hi, h⟩
    refine ⟨i, ?_, by simpa [hi, Expr.eval] using h⟩
    have := Expr.leaves_lt_of_eval h i (by simp [Expr.leaves])
    exact this

theorem reachM_leaf {p : List Nat} {m v : Nat} :
    (∃ i, 2 ^ i = m ∧ (Expr.leaf i).eval p = some v) → ReachM p m v := by
  rintro ⟨i, hi, h⟩
  exact ⟨.leaf i, Expr.legal_leaf i, hi, h⟩

/-- Build a node from two reachable halves of a split in either order -/
theorem reachM_node {p : List Nat} {s r a b v : Nat} (hsr : s &&& r = 0)
    (ha : ReachM p s a) (hb : ReachM p r b) (hv : v ∈ results a b) : ReachM p (s ||| r) v := by
  obtain ⟨ea, hla, hma, hea⟩ := ha
  obtain ⟨eb, hlb, hmb, heb⟩ := hb
  obtain ⟨op, h | h⟩ := mem_results.mp hv
  · refine ⟨.node op ea eb, ?_, ?_, ?_⟩
    · exact (Expr.legal_node_iff _ _ _).mpr ⟨hla, hlb, by rw [hma, hmb]; exact hsr⟩
    · simp [Expr.mask, hma, hmb]
    · simp only [Option.bind_eq_some_iff, pos] at h
      obtain ⟨w, hw, h⟩ := h
      split at h
      · cases h; exact Expr.eval_node.mpr ⟨a, b, hea, heb, hw, by assumption⟩
      · simp at h
  · refine ⟨.node op eb ea, ?_, ?_, ?_⟩
    · refine (Expr.legal_node_iff _ _ _).mpr ⟨hlb, hla, ?_⟩
      rw [hma, hmb, Nat.and_comm]; exact hsr
    · simp [Expr.mask, hma, hmb, or_comm']
    · simp only [Option.bind_eq_some_iff, pos] at h
      obtain ⟨w, hw, h⟩ := h
      split at h
      · cases h; exact Expr.eval_node.mpr ⟨b, a, heb, hea, hw, by assumption⟩
      · simp at h

theorem mem_entry {p : List Nat} {T : List (List Nat)} {m v : Nat} :
    v ∈ entry p T m ↔ v ∈ leafVals p m ∨ ∃ s, s < m ∧ (s ≠ 0 ∧ s &&& m = s ∧ s < m ^^^ s) ∧
      ∃ l ∈ pairs (T.getD s []) (T.getD (m ^^^ s) []), v ∈ l := by
  simp only [entry, mem_mergeAll, List.mem_cons, exists_eq_or_imp, splitVals, List.mem_flatMap,
    List.mem_range]
  apply or_congr Iff.rfl
  constructor
  · rintro ⟨l, ⟨s, hs, hl⟩, hv⟩
    split at hl
    · exact ⟨s, hs, by assumption, l, hl, hv⟩
    · simp at hl
  · rintro ⟨s, hs, hc, l, hl, hv⟩
    exact ⟨l, ⟨s, hs, by rw [ite_eq_left_of_eq_true _ _ (eq_true hc)]; exact hl⟩, hv⟩

/-- Characterise each table entry as exactly the values of legal expressions with that leaf mask -/
theorem mem_buildTable (p : List Nat) (m : Nat) (hm : 0 < m) (v : Nat) :
    v ∈ (buildTable p m).getD m [] ↔ ReachM p m v := by
  induction m using Nat.strongRecOn generalizing v with
  | _ m ih =>
  obtain ⟨k, rfl⟩ : ∃ k, m = k + 1 := ⟨m - 1, by omega⟩
  -- Look up a smaller mask in the previous table
  have look : ∀ s, 0 < s → s < k + 1 → ∀ w, w ∈ (buildTable p k).getD s [] ↔ ReachM p s w := by
    intro s hs hsk w
    rw [getD_buildTable p (by omega)]
    exact ih s hsk hs w
  rw [getD_buildTable_succ]
  -- Note that every stored value is positive
  have posT : ∀ s, 0 < s → s < k + 1 → ∀ w ∈ (buildTable p k).getD s [], 0 < w := by
    intro s hs hsk w hw
    obtain ⟨e, _, _, he⟩ := (look s hs hsk w).mp hw
    exact Expr.eval_pos he
  rw [mem_entry, mem_leafVals]
  constructor
  · rintro (h | ⟨s, hsm, ⟨hs0, hsub, hlt⟩, h⟩)
    · exact reachM_leaf h
    · obtain ⟨hrsub, hdisj, hor, _⟩ := split_facts hsub
      obtain ⟨i, hi⟩ := Nat.exists_testBit_of_ne_zero hs0
      have hrlt : (k + 1) ^^^ s < k + 1 := lt_of_proper hrsub
        ⟨i, testBit_of_and_eq hsub hi, by simp [Nat.testBit_xor, testBit_of_and_eq hsub hi, hi]⟩
      obtain ⟨a, ha, b, hb, hv⟩ :=
        (mem_pairs (posT s (by omega) hsm) (posT _ (by omega) hrlt)).mp h
      rw [look s (by omega) hsm] at ha
      rw [look _ (by omega) hrlt] at hb
      rw [← hor]
      exact reachM_node hdisj ha hb hv
  · rintro ⟨e, hl, hmask, hev⟩
    cases e with
    | leaf i => exact Or.inl ⟨i, hmask, hev⟩
    | node op l r =>
      right
      obtain ⟨hll, hlr, hdisj⟩ := (Expr.legal_node_iff _ _ _).mp hl
      obtain ⟨a, b, ha, hb, hop, hpos⟩ := Expr.eval_node.mp hev
      simp only [Expr.mask] at hmask
      have hd := (Expr.and_eq_zero_iff _ _).mp hdisj
      have hl0 := l.mask_ne_zero
      have hr0 := r.mask_ne_zero
      obtain ⟨hlsub, hlx⟩ := node_facts hdisj
      obtain ⟨hrsub, hrx⟩ := node_facts (show r.mask &&& l.mask = 0 by rw [Nat.and_comm]; exact hdisj)
      rw [or_comm'] at hrsub hrx
      rw [hmask] at hlsub hlx hrsub hrx
      -- Show each child mask is a proper submask
      have hllt : l.mask < k + 1 := by
        obtain ⟨i, hi⟩ := Nat.exists_testBit_of_ne_zero hr0
        refine lt_of_proper hlsub ⟨i, ?_, ?_⟩
        · rw [← hmask]; simp [hi]
        · cases h : l.mask.testBit i
          · rfl
          · exact absurd ⟨h, hi⟩ (hd i)
      have hrlt : r.mask < k + 1 := by
        obtain ⟨i, hi⟩ := Nat.exists_testBit_of_ne_zero hl0
        refine lt_of_proper hrsub ⟨i, ?_, ?_⟩
        · rw [← hmask]; simp [hi]
        · cases h : r.mask.testBit i
          · rfl
          · exact absurd ⟨hi, h⟩ (hd i)
      have hra : ReachM p l.mask a := ⟨l, hll, rfl, ha⟩
      have hrb : ReachM p r.mask b := ⟨r, hlr, rfl, hb⟩
      have hvr : v ∈ results a b := by
        rw [mem_results]; exact ⟨op, Or.inl (by simp [hop, pos, hpos])⟩
      have hvr' : v ∈ results b a := by
        rw [mem_results]; exact ⟨op, Or.inr (by simp [hop, pos, hpos])⟩
      have hne : l.mask ≠ r.mask := by
        intro h
        obtain ⟨i, hi⟩ := Nat.exists_testBit_of_ne_zero hl0
        exact hd i ⟨hi, h ▸ hi⟩
      rcases Nat.lt_or_gt_of_ne hne with hlt | hlt
      · refine ⟨l.mask, hllt, ?_⟩
        refine ⟨⟨hl0, hlsub, by rw [hlx]; exact hlt⟩, ?_⟩
        rw [hlx]
        exact (mem_pairs (posT _ (Nat.pos_of_ne_zero hl0) hllt) (posT _ (Nat.pos_of_ne_zero hr0) hrlt)).mpr
          ⟨a, (look _ (Nat.pos_of_ne_zero hl0) hllt a).mpr hra,
           b, (look _ (Nat.pos_of_ne_zero hr0) hrlt b).mpr hrb, hvr⟩
      · refine ⟨r.mask, hrlt, ?_⟩
        refine ⟨⟨hr0, hrsub, by rw [hrx]; exact hlt⟩, ?_⟩
        rw [hrx]
        exact (mem_pairs (posT _ (Nat.pos_of_ne_zero hr0) hrlt) (posT _ (Nat.pos_of_ne_zero hl0) hllt)).mpr
          ⟨b, (look _ (Nat.pos_of_ne_zero hr0) hrlt b).mpr hrb,
           a, (look _ (Nat.pos_of_ne_zero hl0) hllt a).mpr hra, hvr'⟩

/-- Prove soundness and completeness of entry `m` of the table for every non-empty mask of the pool -/
theorem mem_table (p : List Nat) {m : Nat} (hm : 0 < m) (hmn : m < 2 ^ p.length) (v : Nat) :
    v ∈ (table p).getD m [] ↔ ∃ e : Expr, e.Legal ∧ e.mask = m ∧ e.eval p = some v := by
  unfold table
  rw [getD_buildTable p (by omega)]
  exact mem_buildTable p m hm v

/-- Characterise the reachable list as exactly the solvable targets -/
theorem mem_reachable (p : List Nat) (t : Nat) : t ∈ reachable p ↔ Solvable p t := by
  have hlen : (table p).length = 2 ^ p.length := by
    unfold table; rw [length_buildTable]; have := Nat.two_pow_pos p.length; omega
  simp only [reachable, mem_mergeAll]
  constructor
  · rintro ⟨l, hl, ht⟩
    obtain ⟨i, hi, rfl⟩ := List.getElem_of_mem hl
    simp only [List.length_drop, hlen] at hi
    have hget : ((table p).drop 1)[i] = (table p).getD (i + 1) [] := by
      simp [List.getD_eq_getElem?_getD, List.getElem?_eq_getElem (by omega : i + 1 < (table p).length)]
    rw [hget, mem_table p (by omega) (by omega)] at ht
    obtain ⟨e, he, _, hev⟩ := ht
    exact ⟨e, he, hev⟩
  · rintro ⟨e, he, hev⟩
    have hlt := Expr.mask_lt_of_eval hev
    have h0 := e.mask_ne_zero
    refine ⟨(table p).getD e.mask [], ?_, (mem_table p (by omega) hlt t).mpr ⟨e, he, rfl, hev⟩⟩
    rw [List.getD_eq_getElem?_getD, List.getElem?_eq_getElem (by omega)]
    simp only [Option.getD_some]
    have : (table p)[e.mask] = ((table p).drop 1)[e.mask - 1]'(by simp [hlen]; omega) := by
      simp only [List.getElem_drop]; congr 1; omega
    rw [this]
    exact List.getElem_mem _

/-- Show that the Boolean decision procedure agrees with the definition of solvability -/
theorem solvableB_iff (p : List Nat) (t : Nat) : solvableB p t = true ↔ Solvable p t := by
  simp [solvableB, mem_reachable]

instance (p : List Nat) (t : Nat) : Decidable (Solvable p t) :=
  decidable_of_iff _ (solvableB_iff p t)

end Countdown
