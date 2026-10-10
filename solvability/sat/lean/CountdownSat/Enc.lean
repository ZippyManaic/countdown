import Std.Tactic.BVDecide
import Countdown.Expr

/-! Define the bit-vector encoding of "some legal expression over the pool reaches a target in a set" as a straight-line program of at most five steps -/

namespace Countdown.Sat

/-- Hold the free variables of one program step, where `opm` picks the multiplicative pair and `opi` the inverse operation -/
structure Step (w : Nat) where
  act : Bool
  sa : BitVec 4
  sb : BitVec 4
  opm : Bool
  opi : Bool
  xa : BitVec w
  xb : BitVec w
  r : BitVec w

/-- Give the inactive step used to pad short programs -/
def Step.idle (w : Nat) : Step w := ⟨false, 0, 0, false, false, 0, 0, 0⟩

/-- Conjoin `f k` over every `k < n` -/
def ball : Nat → (Nat → Bool) → Bool
  | 0, _ => true
  | n + 1, f => ball n f && f n

/-- Disjoin `f k` over every `k < n` -/
def bany : Nat → (Nat → Bool) → Bool
  | 0, _ => false
  | n + 1, f => bany n f || f n

/-- Name a register index as a four-bit selector value -/
abbrev sel (j : Nat) : BitVec 4 := BitVec.ofNat 4 j

/-- Read a register, which is a pool number below six and a step result from six on -/
def reg (p : List Nat) (st : Nat → Step w) (j : Nat) : BitVec w :=
  if j < 6 then BitVec.ofNat w (p.getD j 0) else (st (j - 6)).r

/-- Test membership of a natural number in a union of closed intervals -/
def inNat (ivs : List (Nat × Nat)) (v : Nat) : Bool :=
  ivs.any fun iv => decide (iv.1 ≤ v) && decide (v ≤ iv.2)

/-- Test membership of a bit-vector in a union of closed intervals -/
def inIvs (ivs : List (Nat × Nat)) (x : BitVec w) : Bool :=
  ivs.any fun iv => (BitVec.ofNat w iv.1).ule x && x.ule (BitVec.ofNat w iv.2)

/-- Read operand slot `i`, which is slot `a` of step `i / 2` when `i` is even and slot `b` otherwise -/
def slot (st : Nat → Step w) (i : Nat) : BitVec 4 :=
  if i % 2 = 0 then (st (i / 2)).sa else (st (i / 2)).sb

/-- State the constraints on one active step `k` -/
def stepOK (p : List Nat) (ivs : List (Nat × Nat)) (st : Nat → Step w) (k : Nat) : Bool :=
  let s := st k
  let lo := bif s.opi then s.r else s.xa
  let hi := bif s.opi then s.xa else s.r
  -- Read operands only from earlier registers
  s.sa.ult (sel (6 + k)) && s.sb.ult (sel (6 + k)) &&
  -- Tie each operand value to the register it selects
  ball (6 + k) (fun j => (s.sa != sel j || s.xa == reg p st j) && (s.sb != sel j || s.xb == reg p st j)) &&
  -- Keep every result positive
  s.r != 0 &&
  -- Add as xb + xa = r and subtract as xb + r = xa without wrap-around
  (s.opm || (s.xb.zeroExtend (w + 1) + lo.zeroExtend (w + 1) == hi.zeroExtend (w + 1))) &&
  -- Multiply as xb * xa = r and divide as xb * r = xa without wrap-around
  (!s.opm || (s.xb.zeroExtend (2 * w) * lo.zeroExtend (2 * w) == hi.zeroExtend (2 * w))) &&
  -- Order the operands of the commutative operations
  (s.opi || s.sa.ult s.sb) &&
  -- Forbid a result equal to an operand since a smallest solution never has one
  s.r != s.xa && s.r != s.xb &&
  -- Emit steps in post-order so an internal operand forces the previous step to be an operand
  (k == 0 || (s.sa.ult (sel 6) && s.sb.ult (sel 6)) || s.sa == sel (5 + k) || s.sb == sel (5 + k)) &&
  -- Forbid a target value before the last step since a smallest solution never has one
  (!(st (k + 1)).act || !inIvs ivs s.r)

/-- State that the variables describe a program of one to five steps whose last result lies in the intervals -/
def Enc (p : List Nat) (ivs : List (Nat × Nat)) (w : Nat) (st : Nat → Step w) : Bool :=
  (st 0).act &&
  ball 4 (fun k => !(st (k + 1)).act || (st k).act) &&
  ball 5 (fun k => !(st k).act || stepOK p ivs st k) &&
  ball 5 (fun k => !((st k).act && !(st (k + 1)).act) || inIvs ivs (st k).r) &&
  -- Require each result but the last to feed a later step
  ball 4 (fun k => !(st (k + 1)).act ||
    bany (4 - k) (fun d => (st (k + 1 + d)).act &&
      ((st (k + 1 + d)).sa == sel (6 + k) || (st (k + 1 + d)).sb == sel (6 + k)))) &&
  -- Use each register at most once across all active operand slots
  ball 10 (fun i => ball (9 - i) (fun d => !(st ((i + 1 + d) / 2)).act || slot st i != slot st (i + 1 + d)))

/-- Turn five steps into a step function that is idle from step five on -/
def pick (l : List (Step w)) (k : Nat) : Step w := l.getD k (Step.idle w)

/-- Unfold `Enc` on five destructured steps and discharge the resulting bit-vector goal with `bv_decide` -/
macro "enc_unsat" : tactic => `(tactic| (
  intro s0 s1 s2 s3 s4
  cases s0; cases s1; cases s2; cases s3; cases s4
  simp only [Enc, stepOK, ball, bany, reg, slot, pick, inIvs, List.getD_cons_zero, List.getD_cons_succ,
    List.getD_nil, List.any_cons, List.any_nil, Step.idle, Nat.reduceAdd, Nat.reduceSub, Nat.reduceMul,
    Nat.reduceDiv, Nat.reduceMod, Nat.reduceLT, Nat.reduceEqDiff, ite_true, ite_false, Bool.or_false,
    Bool.false_or, Bool.and_true, Bool.true_and]
  bv_decide (config := { timeout := 86400 })))

end Countdown.Sat
