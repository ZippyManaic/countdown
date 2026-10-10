// Check the dealer in every mode and the solver against rounds with known answers
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

// Check one dealt round against its mode and return how many large numbers it holds
private fun checkRound(mode: String, target: Int, pool: IntArray, counts: Set<Int>): Int {
    val large = pool.filter { it > 10 }
    expect(target in 100..999 && pool.size == 6, "$mode deals a target and six numbers")
    expect(large.distinct().size == large.size && LARGE_NUMBERS.getValue(mode).containsAll(large),
        "$mode deals distinct large numbers from its set")
    expect((1..10).all { n -> pool.count { it == n } <= 2 }, "$mode deals each small number at most twice")
    expect(large.size in counts, "$mode deals an allowed large count")
    return large.size
}

private fun testDealer() {
    for ((mode, counts) in listOf("standard" to setOf(1, 2), "cats" to (0..4).toSet(), "nasty" to (0..4).toSet())) {
        val seen = (1..2000).map {
            val (target, pool) = generateRound(Random.Default, mode)
            checkRound(mode, target, pool, counts)
        }.toSet()
        expect(seen == counts, "$mode deals every allowed large count")
    }
    for (mode in listOf("cats", "nasty")) {
        for (k in 0..4) {
            val (target, pool) = generateRound(Random.Default, mode, k)
            expect(checkRound(mode, target, pool, setOf(k)) == k, "$mode deals a fixed large count")
        }
    }
    expect(parseArgs(arrayOf()) == ("standard" to null), "accepts no arguments")
    expect(parseArgs(arrayOf("nasty", "4")) == ("nasty" to 4), "accepts nasty 4")
    expect(parseArgs(arrayOf("cats", "0")) == ("cats" to 0), "accepts cats 0")
    for (bad in listOf(arrayOf("standard", "3"), arrayOf("cats", "5"), arrayOf("easy"), arrayOf("cats", "1", "2"),
            arrayOf("cats", "x"))) {
        expect(parseArgs(bad) == null, "rejects ${bad.joinToString(" ")}")
    }
}

private fun testCatsRounds() {
    expect(Solver.solve(999, intArrayOf(10, 10, 25, 50, 75, 100)) == Result(999, "(((75 + 25) * 100) - 10) / 10"),
        "solves a four-large round")
    expect(Solver.solve(100, intArrayOf(1, 1, 2, 2, 3, 3)) == Result(81, "(((2 + 1) * (2 + 1)) * 3) * 3"),
        "solves a no-large round")
    expect(Solver.solve(999, intArrayOf(2, 3, 87, 62, 37, 12)) == Result(999, "37 * ((87 / 3) - 2)"),
        "solves a nasty round")
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
        testDealer()
        testCatsRounds()
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
