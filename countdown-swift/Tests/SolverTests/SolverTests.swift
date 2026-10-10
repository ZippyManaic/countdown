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

    func testDealsAValidPool() {
        var generator = SystemRandomNumberGenerator()
        for _ in 0..<1000 {
            let (target, pool) = generateRound(using: &generator)
            XCTAssert((100...999).contains(target))
            XCTAssertEqual(pool.count, 6)
            let large = pool.filter { $0 > 10 }.count
            XCTAssert(large == 1 || large == 2)
            for n in 1...10 {
                XCTAssertLessThanOrEqual(pool.filter { $0 == n }.count, 2)
            }
        }
    }
}
