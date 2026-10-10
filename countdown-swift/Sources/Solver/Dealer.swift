// Deal Countdown numbers rounds

// Name the game mode, which sets the large cards and how many may be dealt
public enum Mode: String, CaseIterable, Sendable {
    case standard, cats, nasty

    // Give the four large cards of the mode, with nasty-cats using the cards of the 2010 specials
    public var largeNumbers: [Int] {
        self == .nasty ? [12, 37, 62, 87] : [25, 50, 75, 100]
    }

    // Give the numbers of large cards the mode allows
    public var largeCounts: ClosedRange<Int> {
        self == .standard ? 1...2 : 0...4
    }
}

public let usage = "usage: countdown [standard|cats|nasty] [LARGE]"

// Return a random target and six numbers with one or two large in standard mode and none to four otherwise
public func generateRound<G: RandomNumberGenerator>(
    mode: Mode = .standard, largeCount: Int? = nil, using generator: inout G
) -> (target: Int, pool: [Int]) {
    let target = Int.random(in: 100...999, using: &generator)
    let largeCount = largeCount ?? Int.random(in: mode.largeCounts, using: &generator)
    // Hold two cards of each small number to match the game's deck
    let small = (0..<20).map { $0 % 10 + 1 }.shuffled(using: &generator)
    // Shuffle a copy since each large number appears only once in the game
    let large = mode.largeNumbers.shuffled(using: &generator)
    return (target, Array(small.prefix(6 - largeCount)) + Array(large.prefix(largeCount)))
}

// Return the mode and fixed large count from the command line, or nil when the arguments are invalid
public func parseArgs(_ args: [String]) -> (mode: Mode, largeCount: Int?)? {
    guard args.count <= 2, let mode = Mode(rawValue: args.first ?? "standard") else { return nil }
    guard args.count == 2 else { return (mode, nil) }
    // Match the exact digits so that forms such as "+1" are rejected as in the Python version
    return mode.largeCounts.first { String($0) == args[1] }.map { (mode, $0) }
}
