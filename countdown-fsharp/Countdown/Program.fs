// Generate a Countdown numbers round and work out whether it can be solved
open System
open Countdown

[<EntryPoint>]
let main args =
    match Dealer.parseArgs args with
    | None ->
        eprintfn "%s" Dealer.usage
        2
    | Some(mode, fixedLarge) ->
        let target, pool = Dealer.generateRound Random.Shared mode fixedLarge
        printfn "Target: %d" target
        printfn "Pool:   %s" (String.Join(' ', pool))
        let value, expr = Solver.solve target pool
        if value = target then
            printfn "Solved: %s = %d" expr value
            0
        else
            printfn "No exact solution, closest is %s = %d (%d away)" expr value (abs (value - target))
            1
