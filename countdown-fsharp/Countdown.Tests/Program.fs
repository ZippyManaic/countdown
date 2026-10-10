// Check the solver against rounds with known answers
open System
open Countdown

let mutable failures = 0

let expect ok what =
    if not ok then
        printfn "FAIL: %s" what
        failures <- failures + 1

expect (Solver.solve 125 [| 1; 5; 7; 3; 75; 50 |] = (125, "75 + 50")) "finds simplest solution"
expect (fst (Solver.solve 552 [| 8; 4; 2; 5; 100; 25 |]) = 552) "solves 552"
expect (abs (fst (Solver.solve 974 [| 8; 8; 6; 8; 25; 100 |]) - 974) = 1) "reports closest when unsolvable"
expect (Solver.solve 7 [| 7 |] = (7, "7")) "handles a single number"
expect (Solver.solve 10 [| 3; 4 |] = (12, "4 * 3")) "handles smaller pools"
for _ in 1 .. 1000 do
    let target, pool = Dealer.generateRound Random.Shared
    let large = pool |> Array.filter (fun n -> n > 10) |> Array.length
    let counts = [ 1 .. 10 ] |> List.forall (fun n -> (pool |> Array.filter ((=) n) |> Array.length) <= 2)
    expect (target >= 100 && target <= 999 && pool.Length = 6 && (large = 1 || large = 2) && counts) "deals a valid pool"
if failures > 0 then exit 1
printfn "all tests passed"
