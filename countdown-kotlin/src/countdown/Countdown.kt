// Generate a Countdown numbers round and work out whether it can be solved
package countdown

import kotlin.random.Random
import kotlin.system.exitProcess

private val LARGE_NUMBERS = listOf(25, 50, 75, 100)

// Return a random target and a pool of six numbers with either one or two large numbers
fun generateRound(random: Random): Pair<Int, IntArray> {
    val target = random.nextInt(100, 1000)
    val largeCount = random.nextInt(1, 3)
    // Hold two cards of each small number to match the game's deck
    val small = ((1..10) + (1..10)).shuffled(random)
    // Shuffle a copy since each large number appears only once in the game
    val large = LARGE_NUMBERS.shuffled(random)
    return target to (small.take(6 - largeCount) + large.take(largeCount)).toIntArray()
}

fun main() {
    val (target, pool) = generateRound(Random.Default)
    println("Target: $target")
    println("Pool:   ${pool.joinToString(" ")}")
    val (value, expr) = Solver.solve(target, pool)
    if (value == target) {
        println("Solved: $expr = $value")
        return
    }
    println("No exact solution, closest is $expr = $value (${Math.abs(value - target)} away)")
    exitProcess(1)
}
