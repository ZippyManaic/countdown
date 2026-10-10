// Deal Countdown numbers rounds and read the game mode from the command line
module Countdown.Dealer

open System

// Map each mode to its large cards, with nasty-cats using the cards of the 2010 specials
let largeNumbers =
    Map [ "standard", [| 25; 50; 75; 100 |]; "cats", [| 25; 50; 75; 100 |]; "nasty", [| 12; 37; 62; 87 |] ]

let usage = "usage: countdown [standard|cats|nasty] [LARGE]"

// Return a random target and six numbers with one or two large in standard mode and none to four otherwise
let generateRound (random: Random) (mode: string) (fixedLarge: int option) =
    let target = random.Next(100, 1000)
    let largeCount =
        match fixedLarge with
        | Some k -> k
        | None -> if mode = "standard" then random.Next(1, 3) else random.Next(0, 5)
    // Hold two cards of each small number to match the game's deck
    let small = Array.init 20 (fun i -> i % 10 + 1)
    random.Shuffle small
    // Shuffle a copy since each large number appears only once in the game
    let large = Array.copy largeNumbers[mode]
    random.Shuffle large
    target, Array.append small[.. 5 - largeCount] large[.. largeCount - 1]

// Return the mode and fixed large count from the command line, or None when the arguments are invalid
let parseArgs (args: string[]) =
    let mode = if args.Length > 0 then args[0] else "standard"
    if args.Length > 2 || not (largeNumbers.ContainsKey mode) then None
    elif args.Length < 2 then Some(mode, None)
    else
        let allowed = if mode = "standard" then [ "1"; "2" ] else [ "0"; "1"; "2"; "3"; "4" ]
        if List.contains args[1] allowed then Some(mode, Some(int args[1])) else None
