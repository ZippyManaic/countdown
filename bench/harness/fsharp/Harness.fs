// Time the solver over a file of rounds and write each answer as value tab expression
open System
open System.Diagnostics
open System.IO
open Countdown

[<EntryPoint>]
let main args =
    let rounds =
        File.ReadAllLines args[0]
        |> Array.filter (fun line -> line.Length > 0)
        |> Array.map (fun line -> line.Split(' ', StringSplitOptions.RemoveEmptyEntries) |> Array.map int)
    let reps = if args.Length > 2 then int args[2] else 1
    // Warm up with untimed passes so the timing measures fully compiled code rather than the JIT compiling it
    for _ in 1 .. 3 do
        for r in rounds do
            Solver.solve r.[0] r.[1..] |> ignore
    let output = Array.zeroCreate rounds.Length
    let watch = Stopwatch.StartNew()
    for _ in 1 .. reps do
        for i in 0 .. rounds.Length - 1 do
            let r = rounds[i]
            output[i] <- Solver.solve r.[0] r.[1..]
    watch.Stop()
    eprintfn "%.4f ms/round" (watch.Elapsed.TotalMilliseconds / float (rounds.Length * reps))
    File.WriteAllText(args[1], output |> Array.map (fun (v, e) -> $"{v}\t{e}") |> String.concat "\n")
    0
