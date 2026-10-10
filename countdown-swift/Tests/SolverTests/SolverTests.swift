// Check the solver against rounds with known answers
import Solver
import XCTest

final class SolverTests: XCTestCase {
    func testFindsSimplestSolution() {
        let result = solve(target: 125, pool: [1, 5, 7, 3, 75, 50])
        XCTAssertEqual(result.value, 125)
        XCTAssertEqual(result.expr, "75 + 50")
        XCTAssertEqual(solve(target: 552, pool: [8, 4, 2, 5, 100, 25]).value, 552)
    }

    func testReportsClosestWhenUnsolvable() {
        XCTAssertEqual(abs(solve(target: 974, pool: [8, 8, 6, 8, 25, 100]).value - 974), 1)
    }

    func testReportsLoneNumberAsClosest() {
        let result = solve(target: 100, pool: [7])
        XCTAssertEqual(result.value, 7)
        XCTAssertEqual(result.expr, "7")
    }

    // Deal many rounds in a mode and check each is legal and every allowed large count occurs
    private func checkDeals(_ mode: Mode) {
        var generator = SystemRandomNumberGenerator()
        var seen = Set<Int>()
        for _ in 0..<2000 {
            let (target, pool) = generateRound(mode: mode, using: &generator)
            XCTAssert((100...999).contains(target))
            XCTAssertEqual(pool.count, 6)
            let large = pool.filter { $0 > 10 }
            XCTAssert(large.allSatisfy(mode.largeNumbers.contains))
            XCTAssertEqual(Set(large).count, large.count)
            for n in 1...10 {
                XCTAssertLessThanOrEqual(pool.filter { $0 == n }.count, 2)
            }
            XCTAssert(mode.largeCounts.contains(large.count))
            seen.insert(large.count)
        }
        XCTAssertEqual(seen, Set(mode.largeCounts))
    }

    func testDealsValidPoolsInEveryMode() {
        for mode in Mode.allCases {
            checkDeals(mode)
        }
    }

    func testDealsAFixedLargeCount() {
        var generator = SystemRandomNumberGenerator()
        for mode in [Mode.cats, .nasty] {
            for count in 0...4 {
                let pool = generateRound(mode: mode, largeCount: count, using: &generator).pool
                XCTAssertEqual(pool.filter { $0 > 10 }.count, count)
            }
        }
    }

    func testParsesValidArguments() {
        XCTAssertEqual(parseArgs([])?.mode, .standard)
        XCTAssertNil(parseArgs([])?.largeCount)
        XCTAssertEqual(parseArgs(["nasty", "4"])?.mode, .nasty)
        XCTAssertEqual(parseArgs(["nasty", "4"])?.largeCount, 4)
        XCTAssertEqual(parseArgs(["cats", "0"])?.mode, .cats)
        XCTAssertEqual(parseArgs(["cats", "0"])?.largeCount, 0)
    }

    func testRejectsInvalidArguments() {
        for args in [["standard", "3"], ["cats", "5"], ["easy"], ["cats", "1", "2"], ["cats", "x"]] {
            XCTAssertNil(parseArgs(args), "\(args)")
        }
    }

    func testSolvesCatsRounds() {
        let first = solve(target: 999, pool: [10, 10, 25, 50, 75, 100])
        XCTAssertEqual(first.value, 999)
        XCTAssertEqual(first.expr, "(((75 + 25) * 100) - 10) / 10")
        let second = solve(target: 100, pool: [1, 1, 2, 2, 3, 3])
        XCTAssertEqual(second.value, 81)
        XCTAssertEqual(second.expr, "(((2 + 1) * (2 + 1)) * 3) * 3")
        let third = solve(target: 999, pool: [2, 3, 87, 62, 37, 12])
        XCTAssertEqual(third.value, 999)
        XCTAssertEqual(third.expr, "37 * ((87 / 3) - 2)")
    }
}
