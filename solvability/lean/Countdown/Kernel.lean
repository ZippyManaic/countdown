import Countdown.Pools

/-! Run the same decision procedure as the `native_decide` theorems inside the kernel on the worst pool -/

namespace Countdown

set_option maxRecDepth 100000

/-- Check in the kernel that the worst pool misses exactly 653 targets -/
theorem worst_pool_missCount : missCount [1, 1, 2, 2, 3, 25] = 653 := by
  decide +kernel

/-- Count the worst pool's unsolvable targets in terms of `Solvable` itself -/
theorem worst_pool_unsolvable : (targets.filter fun t => ¬ Solvable [1, 1, 2, 2, 3, 25] t).length = 653 := by
  rw [← missCount_eq]; exact worst_pool_missCount

/-- Check in the kernel that the worst pool reaches 675 and nothing above it -/
theorem worst_pool_max : (reachable [1, 1, 2, 2, 3, 25]).all (· ≤ 675) = true ∧ Solvable [1, 1, 2, 2, 3, 25] 675 := by
  decide +kernel

/-- Rule out every target above 675 for the worst pool -/
theorem worst_pool_above {t : Nat} (ht : 675 < t) : ¬ Solvable [1, 1, 2, 2, 3, 25] t := by
  intro hs
  have h := List.all_eq_true.mp worst_pool_max.1 t ((mem_reachable _ t).mpr hs)
  simp at h; omega

/-- Give an explicit expression for 675 from the worst pool, namely 25 × 3 × (2 + 1) × (2 + 1) -/
theorem worst_pool_675 : Solvable [1, 1, 2, 2, 3, 25] 675 :=
  ⟨.node .mul (.node .mul (.leaf 5) (.leaf 4)) (.node .mul (.node .add (.leaf 2) (.leaf 0))
      (.node .add (.leaf 3) (.leaf 1))), by decide, rfl⟩

/-- Check in the kernel that 179 is the smallest target the worst pool misses -/
theorem worst_pool_179 : ¬ Solvable [1, 1, 2, 2, 3, 25] 179 ∧ ∀ t ∈ List.range' 100 79, Solvable [1, 1, 2, 2, 3, 25] t := by
  decide +kernel

end Countdown
