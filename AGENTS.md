# Notes for coding agents

This repository holds Countdown numbers-round solvers in many languages. The first version was written by Claude Opus 5.5 in Claude Code (see section 12 of `paper/countdown.pdf`). If you are another model or tool auditing or extending it, please follow these rules so your results compare fairly.

## Rules

- **Answers must stay byte-identical.** Check every change with `bench/run.sh -n 3 <language>`. It must report `10000 identical, 0 ties, 0 wrong`, except where `PERFORMANCE.md` lists known ties (Python, the lookup table and the transformer).
- **No state across solves.** Each call to solve allocates its own working memory. Nothing (buffers, bitsets, caches) may carry over to the next call; constant tables are fine. Parallel versions may keep a worker pool alive between solves, as long as it holds no round data.
- **Keep parallel versions separate.** Multi-threaded solvers live in `countdown-<language>-par/` with their own harness, and the single-core project stays untouched.
- **Time fairly.** Single-core benchmarks pin to CPU 0, as `run.sh` does. Re-time C (`bench/run.sh -n 5 c`) in the same session and quote both figures, since timings vary by about 10% between sessions.
- **Keep the notes current.** After any speed change, update the language's row and note in `PERFORMANCE.md`, and list what you tried and rejected, with measurements.
- **Comment style.** Every code comment is UK English, in the imperative mood, one sentence, with no Oxford comma and no trailing full stop. For example: `// Skip the pair when the quotient is not exact`.

## Recording your own cost

To let models be compared, say in your report or commit message which model and tool you are, roughly how many tokens and how much time the work took, and how many variants you measured. Compare against the per-solution figures in `PERFORMANCE.md`'s "What each solution cost" section.

## Where to look for speed

- `PERFORMANCE.md`: "What made the difference", the language notes and "Tried and rejected" record what has already been tried.
- The paper's sections 7 and 10 describe the algorithm and the refinements (a) to (f), and the surprises section has hardware counters for several languages.
- Rust has not had the optimisation pass the other compiled languages had. The ISPC notes describe a values-only structure that a scalar C control ran about 12% faster than the current C solver.
