import Countdown.Pools

/-! Export the per-pool missed targets for comparison with the exhaustive study, outside the proof -/

open Countdown

/-- List the missed targets of a pool using the verified reachable set -/
def missedTargets (p : List Nat) : List Nat :=
  let R := (reachable p).filter fun v => 100 ≤ v && v ≤ 999
  targets.filter fun t => !R.contains t

/-- Format one pool as a TSV row of pool, miss count and missed targets -/
def row (p : List Nat) : String :=
  let ms := missedTargets p
  " ".intercalate (p.map toString) ++ "\t" ++ toString ms.length ++ "\t" ++ ",".intercalate (ms.map toString)

/-- Write one TSV file per large set and number of large numbers -/
def main : IO Unit := do
  IO.FS.createDirAll "out"
  for (name, large) in [("standard", standardLarge), ("nasty", nastyLarge)] do
    for ℓ in [0, 1, 2, 3, 4] do
      let rows := parMap row (pools large ℓ)
      IO.FS.writeFile s!"out/misses_{name}_{ℓ}.tsv" ("pool\tmiss_count\tmissed_targets\n" ++ "\n".intercalate rows ++ "\n")
