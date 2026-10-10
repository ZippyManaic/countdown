// Generate a Countdown numbers round and work out whether it can be solved
import Solver

#if canImport(Glibc)
import Glibc
#endif

var generator = SystemRandomNumberGenerator()
let (target, pool) = generateRound(using: &generator)
print("Target: \(target)")
print("Pool:   \(pool.map(String.init).joined(separator: " "))")
let (value, expr) = solve(target: target, pool: pool)
if value == target {
    print("Solved: \(expr) = \(value)")
} else {
    print("No exact solution, closest is \(expr) = \(value) (\(abs(value - target)) away)")
    exit(1)
}
