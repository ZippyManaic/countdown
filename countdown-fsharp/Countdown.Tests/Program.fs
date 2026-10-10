// Check the dealer in every mode and the solver against rounds with known answers
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
    let target, pool = Dealer.generateRound Random.Shared "standard" None
    let large = pool |> Array.filter (fun n -> n > 10) |> Array.length
    let counts = [ 1 .. 10 ] |> List.forall (fun n -> (pool |> Array.filter ((=) n) |> Array.length) <= 2)
    expect (target >= 100 && target <= 999 && pool.Length = 6 && (large = 1 || large = 2) && counts) "deals a valid pool"

// Check one dealt round against its mode and return how many large numbers it holds
let checkRound mode target (pool: int[]) counts =
    let large = pool |> Array.filter (fun n -> n > 10)
    expect (target >= 100 && target <= 999 && pool.Length = 6) $"{mode} deals a target and six numbers"
    expect (Array.distinct large = large && large |> Array.forall (fun n -> Array.contains n Dealer.largeNumbers[mode]))
        $"{mode} deals distinct large numbers from its set"
    expect ([ 1 .. 10 ] |> List.forall (fun n -> (pool |> Array.filter ((=) n) |> Array.length) <= 2))
        $"{mode} deals each small number at most twice"
    expect (Set.contains large.Length counts) $"{mode} deals an allowed large count"
    large.Length

for mode, counts in [ "standard", set [ 1; 2 ]; "cats", set [ 0 .. 4 ]; "nasty", set [ 0 .. 4 ] ] do
    let seen =
        set [ for _ in 1 .. 2000 ->
                  let target, pool = Dealer.generateRound Random.Shared mode None
                  checkRound mode target pool counts ]
    expect (seen = counts) $"{mode} deals every allowed large count"
for mode in [ "cats"; "nasty" ] do
    for k in 0 .. 4 do
        let target, pool = Dealer.generateRound Random.Shared mode (Some k)
        expect (checkRound mode target pool (set [ k ]) = k) $"{mode} deals a fixed large count"
expect (Dealer.parseArgs [||] = Some("standard", None)) "accepts no arguments"
expect (Dealer.parseArgs [| "nasty"; "4" |] = Some("nasty", Some 4)) "accepts nasty 4"
expect (Dealer.parseArgs [| "cats"; "0" |] = Some("cats", Some 0)) "accepts cats 0"
for bad in [ [| "standard"; "3" |]; [| "cats"; "5" |]; [| "easy" |]; [| "cats"; "1"; "2" |]; [| "cats"; "x" |] ] do
    expect (Dealer.parseArgs bad = None) ("rejects " + String.Join(' ', bad))
expect (Solver.solve 999 [| 10; 10; 25; 50; 75; 100 |] = (999, "(((75 + 25) * 100) - 10) / 10")) "solves a four-large round"
expect (Solver.solve 100 [| 1; 1; 2; 2; 3; 3 |] = (81, "(((2 + 1) * (2 + 1)) * 3) * 3")) "solves a no-large round"
expect (Solver.solve 999 [| 2; 3; 87; 62; 37; 12 |] = (999, "37 * ((87 / 3) - 2)")) "solves a nasty round"
if failures > 0 then exit 1
printfn "all tests passed"
