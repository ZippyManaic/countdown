// Time the solver over a file of rounds and write each answer as value tab expression
import java.io.File

fun main(args: Array<String>) {
    val rounds = File(args[0]).readLines().filter { it.isNotBlank() }
        .map { line -> line.trim().split(Regex("\\s+")).map { it.toInt() }.toIntArray() }
    val reps = if (args.size > 2) args[2].toInt() else 1
    // Warm up with untimed passes so the timing measures fully compiled code rather than the JIT compiling it
    repeat(3) {
        for (r in rounds) countdown.Solver.solve(r[0], r.copyOfRange(1, 7))
    }
    val out = arrayOfNulls<countdown.Result>(rounds.size)
    val start = System.nanoTime()
    repeat(reps) {
        for (i in rounds.indices) out[i] = countdown.Solver.solve(rounds[i][0], rounds[i].copyOfRange(1, 7))
    }
    val ms = (System.nanoTime() - start) / 1e6 / (rounds.size.toDouble() * reps)
    System.err.println(String.format("%.4f ms/round", ms))
    File(args[1]).writeText(out.joinToString("\n") { "${it!!.value}\t${it.expr}" })
}
