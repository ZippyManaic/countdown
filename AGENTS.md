# Notes for coding agents

This repository holds Countdown numbers-round solvers in many languages. The first version was written by Claude Opus 5.5 in Claude Code (see the section "How the implementations were written" in `paper/countdown.pdf`). If you are another model or tool auditing or extending it, please follow these rules so your results compare fairly.

## Rules

- **Answers must stay byte-identical.** Check every change with `bench/run.sh -n 3 <language>` on the standard set and with `--set cats` and `--set nasty`, which deal 0 to 4 large numbers and reach values up to 937,500,000. Each must report `10000 identical, 0 ties, 0 wrong`, except where `PERFORMANCE.md` lists known ties (Python, the lookup table and the transformer). Run the project's own tests too; they cover the dealer in every mode and pools of one and two numbers.
- **No state across solves.** Each call to solve allocates its own working memory. Nothing (buffers, bitsets, caches) may carry over to the next call; constant tables are fine. Parallel versions may keep a worker pool alive between solves, as long as it holds no round data.
- **Keep parallel versions separate.** Multi-threaded solvers live in `countdown-<language>-par/` with their own harness, and the single-core project stays untouched.
- **Time fairly.** Single-core benchmarks pin to CPU 0, as `run.sh` does. Re-time C (`bench/run.sh -n 5 c`) in the same session and quote both figures, since timings vary by about 10% between sessions.
- **Keep the notes current.** After any speed change, update the language's row and note in `PERFORMANCE.md`, and list what you tried and rejected, with measurements.
- **Keep the command line.** Every program takes `[standard|cats|nasty] [LARGE]`, exits 0 when it hits the target, 1 when it cannot and 2 for bad arguments, and keeps that behaviour in any rewrite.
- **Share the working tree safely.** If several agents work at once, never run `git stash`, `git checkout` or anything else that rewrites files outside your own project, and time on a CPU core no one else is using.
- **Comment style.** Every code comment is UK English, in the imperative mood, one sentence, with no Oxford comma and no trailing full stop. For example: `// Skip the pair when the quotient is not exact`.

## Recording your own cost

To let models be compared, say in your report or commit message which model and tool you are, roughly how many tokens and how much time the work took, and how many variants you measured. Compare against the per-solution figures in `PERFORMANCE.md`'s "What each solution cost" section.

## Where to look for speed

- `PERFORMANCE.md`: "What made the difference", the language notes and "Tried and rejected" record what has already been tried.
- The paper's sections 7 and 10 describe the algorithm and the refinements (a) to (f), and the surprises section has hardware counters for several languages.
- `PERFORMANCE.md`'s "Cats and nasty-cats rounds" section shows where large values cost time. A bitset sized by a subset's largest possible value becomes expensive with three or four large numbers, and C now radix sorts sparse subsets instead. Check how your solver zeroes and scans memory sized by value range, not by the number of values.
- Rust has not had the optimisation pass the other compiled languages had. The ISPC notes describe a values-only structure that a scalar C control ran about 12% faster than the current C solver.
