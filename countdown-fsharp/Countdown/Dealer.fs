// Deal Countdown numbers rounds
module Countdown.Dealer

open System

let private largeNumbers = [| 25; 50; 75; 100 |]

// Return a random target and a pool of six numbers with either one or two large numbers
let generateRound (random: Random) =
    let target = random.Next(100, 1000)
    let largeCount = random.Next(1, 3)
    // Hold two cards of each small number to match the game's deck
    let small = Array.init 20 (fun i -> i % 10 + 1)
    random.Shuffle small
    // Shuffle a copy since each large number appears only once in the game
    let large = Array.copy largeNumbers
    random.Shuffle large
    target, Array.append small[.. 5 - largeCount] large[.. largeCount - 1]
