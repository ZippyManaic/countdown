// Check the solver against rounds with known answers
package countdown

import kotlin.random.Random
import kotlin.system.exitProcess

private var failures = 0

private fun expect(ok: Boolean, what: String) {
    if (!ok) {
        println("FAIL: $what")
        failures++
    }
}

object SolverTest {
    @JvmStatic
    fun main(args: Array<String>) {
        expect(Solver.solve(125, intArrayOf(1, 5, 7, 3, 75, 50)) == Result(125, "75 + 50"), "finds simplest solution")
        expect(Solver.solve(552, intArrayOf(8, 4, 2, 5, 100, 25)).value == 552, "solves 552")
        expect(Math.abs(Solver.solve(974, intArrayOf(8, 8, 6, 8, 25, 100)).value - 974) == 1,
            "reports closest when unsolvable")
        expect(Solver.solve(7, intArrayOf(7)) == Result(7, "7"), "handles a single number")
        expect(Solver.solve(10, intArrayOf(3, 4)) == Result(12, "4 * 3"), "handles smaller pools")
        repeat(1000) {
            val (target, pool) = generateRound(Random.Default)
            val large = pool.count { it > 10 }
            expect(target in 100..999 && pool.size == 6 && (large == 1 || large == 2) &&
                    (1..10).all { n -> pool.count { it == n } <= 2 }, "deals a valid pool")
        }
        if (failures > 0) exitProcess(1)
        println("all tests passed")
    }
}
