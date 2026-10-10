// Generate a Countdown numbers round and work out whether it can be solved
import Solver

#if canImport(Glibc)
import Glibc
#endif

guard let (mode, largeCount) = parseArgs(Array(CommandLine.arguments.dropFirst())) else {
    // Write to file descriptor 2 since Swift 6 rejects the shared stderr pointer as unsafe
    _ = (usage + "\n").withCString { write(2, $0, strlen($0)) }
    exit(2)
}
var generator = SystemRandomNumberGenerator()
let (target, pool) = generateRound(mode: mode, largeCount: largeCount, using: &generator)
print("Target: \(target)")
print("Pool:   \(pool.map(String.init).joined(separator: " "))")
let (value, expr) = solve(target: target, pool: pool)
if value == target {
    print("Solved: \(expr) = \(value)")
} else {
    print("No exact solution, closest is \(expr) = \(value) (\(abs(value - target)) away)")
    exit(1)
}
