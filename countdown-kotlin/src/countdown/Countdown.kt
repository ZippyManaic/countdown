// Generate a Countdown numbers round and work out whether it can be solved
package countdown

import kotlin.random.Random
import kotlin.system.exitProcess

// Map each mode to its large cards, with nasty-cats using the cards of the 2010 specials
val LARGE_NUMBERS = mapOf(
    "standard" to listOf(25, 50, 75, 100),
    "cats" to listOf(25, 50, 75, 100),
    "nasty" to listOf(12, 37, 62, 87),
)
const val USAGE = "usage: countdown [standard|cats|nasty] [LARGE]"

// Return a random target and six numbers with one or two large in standard mode and none to four otherwise
fun generateRound(random: Random, mode: String = "standard", fixedLarge: Int? = null): Pair<Int, IntArray> {
    val target = random.nextInt(100, 1000)
    val largeCount = fixedLarge ?: if (mode == "standard") random.nextInt(1, 3) else random.nextInt(0, 5)
    // Hold two cards of each small number to match the game's deck
    val small = ((1..10) + (1..10)).shuffled(random)
    // Shuffle a copy since each large number appears only once in the game
    val large = LARGE_NUMBERS.getValue(mode).shuffled(random)
    return target to (small.take(6 - largeCount) + large.take(largeCount)).toIntArray()
}

// Return the mode and fixed large count from the command line, or null when the arguments are invalid
fun parseArgs(args: Array<String>): Pair<String, Int?>? {
    if (args.size > 2) return null
    val mode = args.getOrElse(0) { "standard" }
    if (mode !in LARGE_NUMBERS) return null
    if (args.size < 2) return mode to null
    val allowed = if (mode == "standard") listOf("1", "2") else listOf("0", "1", "2", "3", "4")
    return if (args[1] in allowed) mode to args[1].toInt() else null
}

fun main(args: Array<String>) {
    val (mode, fixedLarge) = parseArgs(args) ?: run {
        System.err.println(USAGE)
        exitProcess(2)
    }
    val (target, pool) = generateRound(Random.Default, mode, fixedLarge)
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
