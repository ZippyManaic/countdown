// Time the solver over a file of rounds and write each answer as value tab expression
import Foundation

let arguments = CommandLine.arguments
let rounds = try String(contentsOfFile: arguments[1], encoding: .utf8)
    .split(separator: "\n")
    .map { $0.split(separator: " ").compactMap { Int($0) } }
let reps = arguments.count > 3 ? Int(arguments[3])! : 1
var output = [(value: Int, expr: String)](repeating: (0, ""), count: rounds.count)
let clock = ContinuousClock()
let elapsed = clock.measure {
    for _ in 0..<reps {
        for (i, r) in rounds.enumerated() {
            output[i] = solve(target: r[0], pool: Array(r[1...]))
        }
    }
}
let ms = Double(elapsed.components.seconds) * 1e3 + Double(elapsed.components.attoseconds) / 1e15
FileHandle.standardError.write(String(format: "%.4f ms/round\n", ms / Double(rounds.count * reps)).data(using: .utf8)!)
try output.map { "\($0.value)\t\($0.expr)" }.joined(separator: "\n").write(toFile: arguments[2], atomically: false, encoding: .utf8)
