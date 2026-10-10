// Deal Countdown numbers rounds

private let largeNumbers = [25, 50, 75, 100]

// Return a random target and a pool of six numbers with either one or two large numbers
public func generateRound<G: RandomNumberGenerator>(using generator: inout G) -> (target: Int, pool: [Int]) {
    let target = Int.random(in: 100...999, using: &generator)
    let largeCount = Int.random(in: 1...2, using: &generator)
    // Hold two cards of each small number to match the game's deck
    let small = (0..<20).map { $0 % 10 + 1 }.shuffled(using: &generator)
    // Shuffle a copy since each large number appears only once in the game
    let large = largeNumbers.shuffled(using: &generator)
    return (target, Array(small.prefix(6 - largeCount)) + Array(large.prefix(largeCount)))
}
