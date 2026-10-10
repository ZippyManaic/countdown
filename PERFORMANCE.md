# Performance notes

Every implementation solves the same Countdown numbers rounds with the same algorithm and must give byte-identical answers, so the timings compare languages and compilers rather than algorithms.

Last measured: 2026-10-08, with `bench/run.sh -n 3 --whole`. Other work was running on the machine at the time, so these figures are roughly 5–10% slower than a quiet machine gives (C measured 0.0185 ms earlier the same day). JavaScript's figure comes from a re-run, because the full run caught a burst of that other load.

## Current results

Solve time is the best of three runs over 10,000 fixed rounds, measured inside each harness so start-up and output are excluded. Python and bwBASIC are timed on the 1,000-round set because the full set takes over a minute per run. JIT-compiled languages (Java, Kotlin, C#, F#, JavaScript, WebAssembly, Julia, Erlang, Elixir and Ruby with RJIT) are timed after three untimed warm-up passes, so their figures show fully compiled code. Whole-program time is the average of 300 runs of each language's own program, dealing and solving one random round, so it includes process and runtime start-up.

| Language | Solve, ms per round | Straight port, ms per round | Gained by optimising | Whole program, ms per run |
|---|---|---|---|---|
| Rust + CUDA (GPU, batched) | 0.000466 | 0.0107 (first kernel) | 23x | 203 |
| Lookup table (Python, precomputed) | 0.00069 | – | – | 13.4 |
| PyTorch on the GPU (Python, batched) | 0.0157 | 0.142 (first version) | 9.0x | 3,218 |
| Zig (ReleaseFast) | 0.0203 | 0.083 | 4.1x | 0.48 |
| C (Clang) | 0.0208 | 0.118 | 5.7x | 0.39 |
| Julia 1.13 | 0.0208 | 0.259 | 12.5x | 548 |
| C++ (Clang) | 0.0213 | 0.086 | 4.0x | 0.73 |
| FreeBASIC (GCC back end) | 0.0215 | 0.123 | 5.7x | 0.50 |
| x86-64 assembly | 0.0218 | 0.043 (first version) | 2.0x | 0.23 |
| WebAssembly (C in Node 24) | 0.0229 | 0.243 | 10.6x | 17.4 |
| Fortran (gfortran) | 0.0247 | 0.109 | 4.4x | 0.52 |
| Ada (GNAT) | 0.0260 | 0.260 | 10x | 0.78 |
| C# (.NET 10) | 0.0274 | 0.212 | 7.7x | 21.9 |
| Swift | 0.0274 | 0.212 | 7.7x | 1.52 |
| F# (.NET 10) | 0.0287 | 0.332 | 11.6x | 30.3 |
| Go | 0.0330 | 0.190 | 5.8x | 0.64 |
| Pascal (Free Pascal) | 0.0352 | 0.752 | 21x | 0.38 |
| PyTorch with transformer proposals | 0.0354 | – | – | 3,223 |
| Haskell (GHC) | 0.0360 | 0.639 | 17.8x | 0.82 |
| Kotlin (JVM) | 0.0373 | 0.149 | 4.0x | 48.2 |
| Java (OpenJDK 25) | 0.0391 | 0.154 | 3.9x | 34.2 |
| Common Lisp (SBCL) | 0.0472 | 0.446 | 9.4x | 1.51 |
| OCaml | 0.0537 | 0.450 | 8.4x | 0.64 |
| Rust | 0.0557 | 9.7 (first version) | 174x | 0.51 |
| Erlang (BEAM)* | 0.0575 | 0.494 | 8.6x | 73.7 |
| Elixir (BEAM)* | 0.0576 | 0.729 | 12.7x | 83.6 |
| JavaScript (Node 24) | 0.0848 | 0.381 | 4.5x | 24.3 |
| COBOL (GnuCOBOL) | 0.173 | 2.07 | 12x | 1.30 |
| LuaJIT | 0.186 | 0.61 | 3.3x | 2.11 |
| Ruby with RJIT | 0.291 | – | – | 29.0 |
| Forth (`gforth-fast`) | 0.318 | 0.864 | 2.7x | 4.28 |
| Forth (`gforth`) | 0.399 | 1.036 | 2.6x | 7.02 |
| Ruby 3.3 | 0.494 | 2.22 | 4.5x | 29.6 |
| Lua 5.4 | 0.550 | 1.10 | 2.0x | 2.44 |
| Python | 7.23 | 12.0 (first version) | 1.7x | 17.6 |
| BASIC (bwBASIC, line-numbered) | 306 | 1,114 | 3.6x | 282 |

*Erlang and Elixir go beyond the shared algorithm: both leave the four- and five-number subsets unbuilt and search into them instead, stop at the first matching partner, and search outward from the target before building everything when no exact answer exists. Their answers are still byte-identical, but they do less work than the other CPU versions; Erlang built like the other CPU versions measured about 0.22 ms. Erlang first deferred only the five-number subsets (0.162 ms) and was then brought up to Elixir's design, so the two BEAM languages now tie. Julia, Erlang and Elixir were measured on 2026-10-09 in a session where C measured 0.0185 ms.

The FreeBASIC, WebAssembly, F#, Haskell, Kotlin, Common Lisp, OCaml, Ruby and BASIC rows were added on 2026-10-09 with `bench/run.sh -n 3 --whole` in a session where C measured 0.0182 ms, so they read about 10% fast against the older rows. bwBASIC is timed once on the 1,000-round set, like Python, because one pass takes five minutes. Ruby's RJIT row is the standard interpreter's code under the experimental JIT, timed after three warm-up passes; its straight port was not timed under RJIT. The WebAssembly straight port is the first C version compiled to WebAssembly.

The CUDA, lookup table, PyTorch and transformer rows were measured on 2026-10-09 in a quieter session, when C measured 0.0184–0.0188 ms, so PyTorch is about 17% faster than C rather than the 23% the table suggests. The PyTorch figures are throughput for all 10,000 rounds solved as one batch, not the time one round takes, and their whole-program times average 10 runs rather than 300 because each takes about three seconds; see their language notes.

Every row matches the reference answers exactly except three. Python picks a different but equally good answer on about 1.5% of rounds (same distance from the target and the same count of numbers used), the lookup table on 31% and the transformer version on 8%. The harness check reports these as ties; none of the three has a wrong answer.

Rust has not had the optimisation pass the other compiled languages had, so it is the obvious next candidate. Python has only had the first algorithmic improvements.

## Sharing a round across threads

Seven solvers have a separate parallel version (`countdown-<language>-par`, and `countdown-rs-par` for Rust) that splits each round across threads, leaving the single-core projects untouched. Threads build different subsets of the same size, take search tasks in split order with the earliest hit winning, and share the whole-pool closest pass by taking the minimum key, so the answers stay byte-identical at every thread count. Each keeps a worker pool alive between solves, holding no round data, because creating threads inside a solve costs more than C's whole solve. Rounds that finish within four numbers stay on one thread.

`bench/scale.sh` times each one at several thread counts, best of three passes over the 10,000 rounds, and accepts a time only if every answer still matches. CPUs 0–15 are the eight performance cores with two hardware threads each and CPUs 16–31 the efficiency cores. The single threads run on CPU 0, and 2, 4 and 8 threads use one hardware thread on each of that many performance cores. 16 threads is run two ways: both hardware threads on all eight performance cores (P+HT), and the eight performance cores plus eight efficiency cores (P+E).

| Solver | 1 | 2 | 4 | 8 | 16 (P+HT) | 16 (P+E) | 32 | Best speed-up |
|---|---|---|---|---|---|---|---|---|
| C | 0.0187 | 0.0159 | 0.0142 | **0.0132** | 0.0153 | 0.0148 | 0.0236 | 1.42x at 8 |
| Julia | 0.0208 | 0.0173 | **0.0154** | 0.0161 | 0.0181 | 0.0180 | 0.0233 | 1.35x at 4 |
| Rust | 0.0461 | 0.0326 | 0.0253 | **0.0228** | 0.0258 | 0.0290 | 0.0416 | 2.02x at 8 |
| Java | 0.0334 | 0.0275 | **0.0222** | 0.0266 | 0.0342 | 0.0421 | 0.0465 | 1.50x at 4 |
| Go | 0.0296 | 0.0272 | **0.0267** | 0.0317 | 0.0429 | 0.0544 | 0.0660 | 1.11x at 4 |
| Elixir* | 0.0549 | 0.0416 | **0.0316** | 0.0318 | 0.0469 | 0.0440 | 0.0595 | 1.74x at 4 |
| Erlang* | 0.0568 | 0.0444 | **0.0330** | 0.0355 | 0.0539 | 0.0453 | 0.0761 | 1.72x at 4 |

Times are ms per round and speed-ups are against the same code on one thread. *Built on the BEAM single-core shortcuts, as in the main table. The BEAM rows were re-measured after Erlang was brought up to Elixir's design and Elixir's 32-thread hang was fixed; the other rows come from the same day's full sweep.

With 8 threads, the default in `bench/run.sh`, the whole program takes 0.78 ms for C, 1.42 for Rust, 3.40 for Go, 34.7 for Java, 66.4 for Erlang, 85.1 for Elixir and 961 for Julia, whose figure is mostly compiling the pool code.

What the sweep shows:

- **Every solver peaks at 4 or 8 threads and then gets slower.** About 46% of rounds finish within four numbers and never go parallel, and the five-number level has only six subsets to share out, so there is little for a ninth thread to do. Past that point each extra thread adds hand-off and wake-up cost, more per-thread scratch to allocate for every solve and more cores contending for the shared cache, with nothing to gain.
- **At 32 threads only Rust still beats one thread.** C is 1.26 times slower than on one thread, Java 1.39, Erlang 1.34 and Go 2.2. Each phase waits for its slowest thread, which is now either an efficiency core running at about half speed or a hardware thread sharing a core with another worker.
- **Hardware threads and efficiency cores hurt about equally at 16.** For C, Julia and Elixir, P+HT and P+E are within 10% of each other, both slower than 8. Go, Java and Rust do worse with efficiency cores and Erlang better; we have not measured why.
- **Rust gains most because its parallel version is also a better single-core solver.** The parallel crate, run on one thread (`rust-par1`, 0.046 ms), is already faster than the single-core Rust (0.056 ms), which has not had the optimisation pass, and it starts from a slower single thread than C, so the same absolute saving is a larger ratio.
- **Only hand-written spinning pools paid.** Handing work to a spinning pool cost 0.3 µs in Rust and 0.6 µs in Java, against 8.5 µs for rayon and 11–12 µs for Java's fork-join pool and virtual threads, on rounds of 20–60 µs. Fork-join was slower than not going parallel at all. Julia's `@spawn` came closest, about 7% behind its spinning pool.
- **Memory management decides the garbage-collected versions.** Go at its default setting was slower with 4 workers than with one, because each worker allocates a bitset of up to about 1 MB per round; it now raises the collector's threshold. Julia's collector stops every thread, so its per-thread bitsets are allocated with `calloc`, outside the collector. C pays too: allocating each thread's scratch afresh for every solve adds 44% to the build work, a cost of the no-reuse rule.
- **On BEAM, copying is the cost to avoid.** Processes share no memory. The first parallel Erlang copied each built value list to every worker and gained only 1.4x. Following Elixir, each worker now rebuilds the small subsets itself from the target and pool, the three-number subsets are passed once as a binary, and tasks are claimed through `atomics` counters.
- **The BEAM schedulers need telling to stay awake.** Idle schedulers sleep and the VM packs work onto fewer of them, so the Erlang version runs with `+sbwt very_long +swt very_low +scl false`. Elixir's dirty schedulers spun and stole processors from the real work until they were switched off, and 2 threads ran slower than 1 until then.

**A race found at 32 threads.** The first full sweep hung in Elixir at 32 threads, using every CPU for three hours. The caller read the current best task once and then waited for every task below it to finish. Meanwhile a worker could lower the best, and another worker would then skip a task at or above the new best without marking it done, so the caller waited for it forever. The caller now re-reads the best on every poll and stops waiting once it reaches it. The window only opens when about 30 workers really run at once, but the Erlang port, which copied the design, deadlocked about once in 15 runs at 4 schedulers before it got the same fix. The parallel Erlang version also blocks in `receive` between phases instead of spinning, so it degrades rather than crawls when there are more schedulers than CPUs.

## What each solution cost

Measured on 2026-10-10. Each row covers both the straight port and the optimised version, since they were written together.

| Solution | Solver lines | Total lines | Clean build, s | Peak memory, MB | Claude output tokens | Claude hours |
|---|---|---|---|---|---|---|
| Python | 95 | 95 | – | 13.4 | 20,545 | 0.18 |
| Lookup table | 97 | 152 | – | 217.1 | 13,196 | 0.11 |
| PyTorch | 427 | 481 | – | 1455.7 | 116,284 | 0.46 |
| PyTorch with transformer | 291 | 419 | – | 1805.3 | 12,823 | 0.27 |
| Rust + CUDA | 804 | 885 | 2.57 | 112.9 | 59,627 | 0.13 |
| Rust | 308 | 308 | 1.28 | 12.0 | 60,269 | 0.22 |
| Assembly | 923 | 1,107 | 0.06 | 4.7 | 101,727 | 0.21 |
| C | 398 | 461 | 0.32 | 4.8 | 67,720 | 0.20 |
| C++ | 372 | 438 | 0.75 | 7.0 | 17,681 | 0.06 |
| Zig | 364 | 446 | 10.02 | 5.3 | 24,461 | 0.11 |
| Go | 451 | 488 | 0.19 | 7.3 | 33,046 | 0.11 |
| Fortran | 528 | 603 | 0.38 | 5.8 | 29,583 | 0.08 |
| Pascal | 598 | 681 | 0.10 | 5.4 | 28,793 | 0.13 |
| COBOL | 926 | 1,056 | 0.35 | 17.0 | 67,559 | 0.17 |
| Lua 5.4 / LuaJIT | 385 | 444 | – | 9.8 / 15.5 | 33,889 | 0.12 |
| Forth (gforth / fast) | 291 | 338 | – | 15.7 / 15.5 | 32,753 | 0.11 |
| JavaScript | 338 | 389 | – | 124.0 | 23,179 | 0.08 |
| Ada | 506 | 592 | 0.56 | 7.7 | 24,689 | 0.06 |
| Java | 414 | 453 | 0.37 | 194.7 | 20,004 | 0.07 |
| C# | 395 | 443 | 2.60 | 54.3 | 17,879 | 0.06 |
| Swift | 378 | 410 | 1.58 | 22.0 | 20,101 | 0.06 |
| WebAssembly | 415 | 517 | 0.25 | 63.2 | 24,711 | 0.35 |
| F# | 346 | 390 | 2.61 | 56.9 | 33,668 | 0.24 |
| Kotlin | 375 | 398 | 7.36 | 193.8 | 24,329 | 0.21 |
| Ruby / RJIT | 269 | 309 | – | 39.6 / 108.7 | 40,853 | 0.26 |
| Common Lisp | 333 | 390 | 0.56 | 92.9 | 37,088 | 0.22 |
| Haskell | 344 | 399 | 2.14 | 24.5 | 36,694 | 0.22 |
| OCaml | 343 | 389 | 0.25 | 14.9 | 53,674 | 0.27 |
| FreeBASIC | 413 | 477 | 0.36 | 5.4 | 65,469 | 0.47 |
| BASIC (bwBASIC) | 143 | 190 | – | 9.7 | 55,377 | 0.48 |
| Julia | 347 | 397 | – | 309.2 | 65,650 | 0.48 |
| Erlang | 454 | 478 | 0.34 | 101.8 | 86,251 | 0.88 |
| Elixir | 306 | 372 | – | 102.9 | 84,789 | 0.70 |
| C, parallel | 664 | 727 | 0.33 | 12.1 | 68,725 | 0.45 |
| Rust, parallel | 586 | 628 | 1.66 | 8.2 | 41,161 | 0.36 |
| Go, parallel | 660 | 697 | 0.16 | 16.0 | 60,409 | 0.45 |
| Java, parallel | 681 | 720 | 0.43 | 741.9 | 44,754 | 0.46 |
| Julia, parallel | 596 | 647 | – | 318.5 | 63,682 | 0.68 |
| Erlang, parallel | 887 | 911 | 0.41 | 106.4 | 159,556 | 2.11 |
| Elixir, parallel | 552 | 628 | – | 129.7 | 160,739 | 1.88 |
| General work: paper, notes, benchmarks and discussion | | | | | 434,656 | 7.93 |
| **Total** | | | | | 2,468,044 | 22.09 |

- **Lines** are lines of code without blank lines or comments, from `bench/loc.py`. Solver lines count only the files that implement solve. Total lines add the program, the tests and any other source in the project, but not build files. WebAssembly counts the C solver it compiles. Python is one file that also deals the rounds.
- **Clean build** is the time `bench/run.sh` takes to build the benchmark binary from an empty build directory, from `bench/metrics.sh`. Toolchain caches stay warm, so the standard libraries are not compiled again. Cargo and Go get fresh caches, so Rust's figures include compiling `rand` and, for CUDA, `cudarc`. Interpreted solvers, and Julia and Elixir, which compile when they start, show –; that cost is in their whole-program time. The PyTorch and lookup-table builds install packages, train a model or compute a 248 MB table, so they are left out.
- **Peak memory** is the maximum resident set size of one benchmark pass over the 10,000 rounds (1,000 for Python and bwBASIC), from `/usr/bin/time`. It includes the runtime and the rounds, and the parallel versions run 8 threads.
- **Claude tokens and hours** come from `bench/agent_cost.py`, which reads this project's Claude Code transcripts. Each response is charged to the solutions its tool calls touch, found from project directories, harness files and `run.sh` arguments, and split evenly when there are several. A subagent's responses are charged only to the solutions it was asked to write, even when it read another project to port it. Output tokens are exact for the main conversation. Subagent transcripts record usage before a response finishes streaming, so their output is estimated from the length of what they wrote, at 0.37 tokens per visible character and 0.30 per character of hidden reasoning. That fit explains 98% of the variation in the main conversation's exact counts. Input tokens, mostly cached context re-read on every call, add up to 415 million and are not shown. Hours are the time from each response to the next response or user message, capped at 15 minutes. Subagents worked in parallel, so their hours overlap and add up to more than the elapsed time.

What stands out:

- **Lines of code track the language more than the speed.** Python, at 95 lines including dealing the rounds, and bwBASIC, at 143, are the shortest; assembly and COBOL, at over 900, the longest. The parallel versions are 1.5 to 2 times their single-core sources, mostly for the pool, the phase hand-offs and the shared search.
- **Most builds take under a second.** The exceptions are Zig at 10 s, Kotlin at 7.4 s and .NET at 2.6 s, each dominated by the compiler rather than the solver.
- **Ahead-of-time compiled CPU solvers need under 25 MB**, except SBCL's 93 MB heap. The JVM uses about 195 MB, rising to 742 MB for the parallel Java version, while Julia uses 310 MB and the BEAM about 100 MB. PyTorch needs 1.5 to 1.8 GB of host memory.
- **Debugging costs more than writing.** The two parallel BEAM versions were the most expensive work, at about 160,000 output tokens and two hours each, including finding the waiting race and tuning the schedulers. Next come PyTorch (116,000) and assembly (102,000), the two least conventional designs. Ports of an existing optimised design were cheapest: C++, C#, Java, Swift and the lookup table each took under 21,000 output tokens.
- **General work was about 18% of the output.** That covers the paper, these notes, benchmark runs across all solutions and discussion.

## How it is measured

- **Machine:** Intel Core i9-13900HX on Linux 7.0, with every benchmark pinned to core 0, a performance core, by `taskset`.
- **Rounds:** `bench/data/rounds1k.txt` (seed 42) and `bench/data/rounds10k.txt` (seed 7), dealt by the Python program, with two to five small numbers from a deck holding two of each from 1 to 10 and one or two large numbers.
- **Reference answers:** `bench/data/ref1k.tsv` and `bench/data/ref10k.tsv`, produced by the Rust version. `bench/check.py` compares any harness's output with them.
- **Harnesses:** `bench/harness/` holds one per language. Compiled languages that can expose a C function (C, C++, assembly, Fortran and COBOL) share `c_harness.c`; the rest have their own. Each takes a rounds file, an output file and a repeat count, times only the solving and prints `<n> ms/round`.
- **JIT warm-up:** the Java, C# and JavaScript harnesses solve every round three times before timing. The PyTorch harness solves the whole batch twice first, so CUDA start-up and Triton kernel compilation are excluded. The CUDA harness keeps solving for a full second first, because the laptop GPU idles at 210 MHz and needs that long to reach its boost clock.
- **GPU power:** in the "balanced" power profile the laptop capped the GPU at 25 W (1.4 GHz) instead of its 115 W default, which made the CUDA version about 50% slower. The CUDA figures were measured in the "performance" profile; the PyTorch ones barely changed between the two. With only a thousand warm-up rounds Java measured 0.065 ms instead of 0.039, because HotSpot had not finished optimising.
- **Noise:** the clock speed varies with temperature, so the same binary can measure up to 10% apart a few minutes later. While optimising, compare variants by CPU cycles (`perf stat -e cpu_core/cycles/`) or run them back to back, not against old wall-clock numbers.
- **No state between solves:** each call to `solve` allocates its own working memory and frees it, and nothing a solve computes is reused by the next. The assembly version's static buffers are the one exception. COBOL and Forth keep a small static table of subset splits that depends only on the pool size. The lookup table and the trained model are precomputed files loaded once, which is the whole point of those two versions.

To refresh the numbers:

```sh
bench/run.sh                 # all languages, best of five, solve time only
bench/run.sh -n 3 --whole    # also time each language's own program
bench/run.sh c go rust       # only some languages
```

## The shared algorithm

Each subset of the six pool numbers is a bitmask. The solver works up through subset sizes, and for each size first checks whether any subset can make the target without building its values: it tries every number that combines with each value of one half to make the target and binary searches the other half for it. Only if no subset of that size hits the target are the subsets' reachable values built, by combining every pair of values across every split. Each value keeps the first way found to make it, and ties between equally good answers are broken the same way everywhere, which is what makes the outputs byte-identical.

## What made the difference

These techniques carried over to most languages, roughly in order of impact:

1. **Stop at the first size that hits the target** and check for the target by searching the two halves rather than building the subset. Most rounds never build five-number subsets.
2. **Drop duplicate values as they are made** with a bitset (or a byte per value stamped with the subset's mask), so duplicates never reach the sort.
3. **Store each value in 16 bytes** (value, operator, masks and both operands) and write it without a branch, advancing the output pointer only when the value is new.
4. **Test division with a reciprocal**: multiply by 1/y, round and multiply back, which is exact for values below 2^27 and avoids a slow divide instruction.
5. **Split each pair loop in two**: right-hand values up to the left value, then the rest, so the larger operand never needs testing.
6. **Sort by rank in the bitset** (a running population count per word), which needs no comparisons.
7. **Make unpredictable comparisons branchless**, above all the binary search, because compilers often turn them back into branches.
8. **Work out each subset's largest value up front** so the bitset is sized exactly and grows only when larger subsets are built.

## Language notes

**C.** Clang compiles the hot loops about 10% faster than GCC, so the Makefile uses Clang. Clang ignored a hint asking for a conditional move in the binary search, so the search adds `(value <= target) * half` instead. Listing subsets in size order up front removed another unpredictable branch. C ends slightly faster than the hand-written assembly because Clang allocates registers better.

**C++.** The same design as C, with templates and lambdas instead of macros and buffers that skip zero-filling. The straight port beat straight C because `std::sort` is generated for the entry type and inlined, where C's `qsort` calls its comparison through a pointer. Clang beats GCC by about 20% here.

**Zig.** Zig's default allocator returns large blocks to the kernel on every free, which cost 255,000 page faults and half the run time; the program now links libc and passes `std.heap.c_allocator`. Growing buffers by doubling rather than Zig's 1.5x saved another 5%. `@branchHint(.unpredictable)` gets a conditional move in the binary search. Linking libc made start-up slower, so whole-program time rose from 0.33 to 0.44 ms.

**Assembly.** GNU `as` in Intel syntax using only Linux system calls. The final gains came from the rank sort, branchless stores, conditional moves in the binary search and a branchless division test. A SIMD rewrite was ruled out because removing duplicates is inherently serial.

**Fortran.** gfortran only inlines the store routine at `-O3`. Default values on the entry type made every allocation zero its whole array, so they were removed. Passing each array to the hot loops as a separate argument let gfortran assume they do not overlap, and gfortran turned `merge` into a branch, so the division test and binary search use arithmetic masks. LLVM Flang was 50% slower. Most of the remaining gap to C is GCC against Clang.

**Go.** A third of the time was the garbage collector rescanning the benchmark harness's 20,000 small objects, fixed by keeping the harness's data flat. `GOAMD64=v3` (set in the Makefile) enables BMI2 and `popcnt`. Go has no way to ask for a conditional move, so two branches became arithmetic masks, and `lookup` was trimmed to fit the inliner's budget of 80. The store routine uses `unsafe` to skip bounds checks. Go still executes about 1.75 times as many instructions as C because its compiler keeps spilling registers.

**Pascal.** Free Pascal's heap manager also returns large blocks to the kernel; using the `cmem` unit (the C library's allocator) halved the time. Free Pascal treats `1.0` as a single-precision constant, which made the reciprocal too inexact to be safe, fixed with `{$minfpconstprec 64}`. Its code generator still produces about twice the instructions of Clang.

**Rust.** Optimised in stages from 9.7 ms: values only while searching, stopping at the first size that hits the target, compact entries with a bitset, and searching halves for the target. It has not yet had the assembly-derived techniques.

**COBOL.** GnuCOBOL turns `MULTIPLY`, `DIVIDE`, `COMPUTE` and the `B-AND` and `B-OR` operators into calls to GMP's decimal arithmetic; only `ADD`, `SUBTRACT`, comparisons, subscripts and moves between same-sized fields become native code. The optimised version uses only that subset in its hot paths:
- multiplication by shift and add and division by long division
- products and quotients carried forward as one operand rises through sorted values
- a byte per value stamped with the subset's mask instead of a bitset
- a byte radix sort reading each value's bytes through `REDEFINES`
- each subset's splits precomputed into a table

That cut decimal arithmetic from about 65% of the time to 3%. Moving a literal into a binary field also goes through a generic routine, so constants live in fields.

**Lua.** One `solver.lua` runs on both Lua 5.4 and LuaJIT by avoiding the operators LuaJIT cannot parse. Each value's origin packs into one number, so the hot loops create no tables. LuaJIT cannot compile `table.sort`, so on LuaJIT the solver uses a radix sort written in Lua, while Lua 5.4 keeps `table.sort` because the radix sort is three times slower in its interpreter. Pre-sizing LuaJIT's hash tables at twice the pair count saved 20%.

**Forth.** Gforth is a threaded-code interpreter, so cost tracks the number of primitives executed. The optimised version uses a byte per value stamped with the subset's mask, a byte radix sort, pointer stepping in the pair loops, and `]] ... [[` macros to compile the hot words in place. Whole-program time is high because Gforth compiles the source on every run.

**Ada.** GNAT 14 uses the GCC back end, so Ada lands alongside Fortran. The straight port keeps Ada's default runtime checks; the optimised build adds `-O3 -gnatn -gnatp -march=native`, suppressing checks and inlining across units. Because `-gnatp` would hide an out-of-range access, the optimised solver was also run over all 10,000 rounds with checks on, giving identical answers. Subset masks need a modular type for `and` and `xor`, GCC's popcount builtin is imported as an intrinsic, `Long_Float'Machine_Rounding` compiles to one rounding instruction, and `Lookup` needed an explicit `Inline`.

**Java.** OpenJDK 25 with HotSpot. The straight port was first recorded at 0.257 ms, before the harness ran three full warm-up passes; re-timed with the current harness on 2026-10-09 it takes 0.154 ms, the same as Kotlin's straight port. The optimised version stores entries as pairs of words in a `long[]` and uses the `Long.bitCount` intrinsic for the rank sort; straight-line code for the partner checks helped slightly. Warm-up matters more than for any other language: the timing only settles after a few full passes. Whole-program time is the slowest of all at 34 ms because the JVM has to start.

**C#.** .NET 10 with RyuJIT. The optimised version is almost a line-for-line port of the C, using `unsafe` pointers over buffers from `NativeMemory` (the C library's allocator), `BitOperations.PopCount` and `AggressiveInlining`, which makes it the fastest of the garbage-collected languages. Runtime settings such as tiered compilation made no clear difference.

**Swift.** Swift 6.1. The optimised version uses `UnsafeMutablePointer` buffers and wrapping arithmetic. Building with `-Ounchecked` (removing overflow and bounds checks, set in `Package.swift` for release builds) took it from 0.043 to 0.030 ms. Swift compiled the exact-division ternary and the binary search's ternary to branches, so both became arithmetic masks, cutting mispredictions by a third. It still executes about 1.7 times C's instructions. The whole program takes 1.5 ms because of Swift's runtime libraries.

**JavaScript.** Node 24 with V8. The optimised version stores four 32-bit words per entry in a `Uint32Array`. JavaScript's bitwise operators work on 32 bits, so the bitset has twice as many words as C's and the population count is done with shifts and masks. Creating typed-array views inside the insertion sort cost allocation and garbage collection, so it copies words by hand. Whole-program time is 24 ms, mostly Node's start-up.

**PyTorch (GPU).** `countdown-torch/` is still Python, but every step runs as PyTorch tensor operations over the whole batch of rounds on an RTX 4070 Laptop GPU, and it gives byte-identical answers. Every value every built subset can make, across all rounds, lives in one sorted `int64` array keyed by subset size, round, subset and value, so lookups are `torch.searchsorted` and a round is dropped from the batch as soon as some size hits its target. Building a level forms every pair across every split as one flat array, removes duplicates with a stable radix sort (equal keys stay in building order, so the first way of making each value wins), and expressions are typeset on the GPU: each node's characters are placed by a prefix sum and copied back as one block of text. The steps from 0.142 ms:
- rendering expressions on the GPU instead of in a Python loop: 0.142 to 0.038 ms
- `torch.compile` fusing pair generation into one Triton kernel, removing the intermediate arrays: 0.030 ms
- scanning the shorter half when searching, with the tie-break comparing operand values rather than positions, and building five-number subsets only for rounds the whole pool cannot hit exactly, working out the others from four-number subsets: 0.0167 ms
- dropping illegal results before the sort: 0.0157 ms

The GPU is then busy for the whole run, and about 30% of that is the radix sort. Batch size is everything: one round takes 11 ms (slower than plain Python), 100 rounds take 0.14 ms each, 1,000 take 0.021 ms and 10,000 take 0.0157 ms. On the CPU (`COUNTDOWN_DEVICE=cpu`, one core) the same code takes 0.53 ms, still 14 times plain Python. The whole program takes over three seconds because importing PyTorch and starting CUDA dominates.

**Rust + CUDA.** `countdown-cuda/` is a Rust crate (using `cudarc`) that launches a CUDA C kernel, compiled by `nvcc` from `build.rs`, and it gives byte-identical answers. It was also checked against the C solver on 20,000 random rounds with two to five numbers. Each thread block takes one round at a time from a shared counter and solves it entirely in shared memory: every subset's values go into one hash table keyed by subset and value, so duplicates are dropped by an atomic compare-and-swap and nothing needs sorting. The searches use the C version's scheme, scanning one half of a split and looking up each value's partners in the other, with ties broken by comparing operand values rather than positions. Five-number subsets are built only when the whole pool cannot hit the target, as in the PyTorch version, and the expression is written out by the block itself. All 10,000 rounds take 4.7 ms: 3.6 ms in the kernel, the rest copying and making Rust strings. The whole program takes 203 ms, almost all of it creating the CUDA context. The steps from 0.0107 ms:
- the first kernel was stalled on barriers 94% of the time, because thread 0 listed every split at each level and each thread searched the splits one after another; precomputing the split tables once per block and flattening each phase into one pool of work items across all splits with a block-wide prefix sum: 0.00138 ms
- keeping four-number subsets as a hash table only, since searches look them up but never scan them, cutting shared memory from 59 to 47 KB so two blocks fit on each SM: 0.00075 ms
- a 5,120-slot table and smaller job lists, so three blocks fit: 0.00073 ms
- appending small subsets' values straight to lists reserved from the pair counts instead of scanning the table afterwards, and not zeroing output buffers the kernel overwrites: 0.00056 ms
- in performance mode, unfolding the answer a tree level at a time, laying out the text without recursion, and building Rust strings without lossy conversion: 0.000466 ms

Each round still runs through dozens of barrier-separated phases with little work in each, so the SMs issue an instruction on only about half of all cycles (6% for the first kernel).

**Lookup table.** `countdown-table/` is plain CPython with no solver at all. Only 9,498 different pools can be dealt (one or two large numbers and up to two of each small number) and there are 900 targets, so `make` has the PyTorch solver answer all 8,548,200 rounds once (165 seconds) and writes them to a 248 MB file. `solve` sorts the pool, finds its row in a dictionary and reads the answer through `mmap`, so a run only touches the pages it needs and the whole program is faster than plain Python's. Each answer takes about 0.7 µs, 27 times faster than C; the harness repeats the lookups 20 times because one pass takes only 7 ms. The table is keyed by the sorted pool, so its answer is the one the solver gives for the pool in ascending order; the shared algorithm breaks ties by position, so 31% of answers are a different, equally short expression from the reference's. Making it byte-identical would mean keying on the dealt order, about 430 million answers. Rounds outside the table fall back to the plain Python solver.

**Transformer proposals.** `countdown-ml/` trains a 4.8-million-parameter decoder-only transformer (six layers, width 256) on 3 million rounds solved by the PyTorch solver, taking 7 minutes on the GPU, to write the reference answer in postfix with numbers named by pool position. Decoding is constrained so every proposal is a legal Countdown expression, and a proposal is kept only if it hits the target. A proposal using k numbers is then accepted only after the exact solver has searched every smaller size and found nothing, which needs only the smaller subsets built. That never gives a wrong answer and saves building four-number subsets for the rounds whose five-number answer it proposed. The model hits the target with the fewest numbers on 42% of rounds overall, but only on 25% of five-number rounds and 7% of six-number rounds, which are the costly ones. Greedy decoding of 10,000 rounds takes 218 ms against the 157 ms the exact solver needs for everything, so the hybrid is 2.3 times slower than the solver alone. Four beams find more answers but take 0.15 ms per round. Getting decoding that fast meant replacing flash attention, which is slow for one query over a 22-token context, with plain matrix products over a preallocated cache, cutting it from 700 ms. On its own the model gives a shortest answer for at most 42% of rounds, which also rules out using it to compress the lookup table: corrections for the rest would take more space than packing each answer into 4 bytes.

**Python.** Has had the first round of algorithmic improvements only: values without origins while searching, and origins rebuilt for the answer.

**FreeBASIC.** FreeBASIC 1.10.1 compiles through GCC. The optimised version is a close port of the C, using typed pointers, `#macro` versions of C's pair, operator and emit macros, the 16-byte branchless store, the reciprocal division test, the rank sort and a branchless binary search. `-Wc -march=native` matters: without it the population count is not a single instruction and the time is 0.029 ms. The last 13% came from replacing `IIf` in the division test with `q And (q * y = x)`, because FreeBASIC turns `IIf` into a mispredicted branch (a true comparison is −1, so `And` works as a mask). It ends about 16% behind C built with Clang but ahead of the same C built with GCC (0.0233 ms), so the gap is GCC against Clang. Identifiers are case-insensitive, so a variable `pairs` clashed with the `PAIRS` macro.

**BASIC (bwBASIC).** A line-numbered interpreter in the 1980s style. Cost tracks statements and operators executed, about 2.4 µs per statement plus 1 µs per operator, with a fifth of the time in `strcmp`. bwBASIC finds every `GOTO` and `GOSUB` target by searching from the start of the program, so a jump near the end costs about 3 µs against 0.4 µs near the start, and the optimised solver puts its hot subroutines first. The optimised version stores only values in one hash table keyed by subset × 2^27 + value, with no sort and no stored origins, and rebuilds the answer's origins with `FindExact`; that gave 3.6x. Quirks met on the way: a `FOR` loop over an empty range still runs once, a nested single-line `IF ... THEN IF` ignores the inner condition, `AND` works only on 32-bit signed values, `\` is not integer division, `TIMER` counts whole seconds, `SYSTEM` cannot set an exit code, and `OPEN` crashes on paths of about 128 characters or more. Yabasic is about 80 times faster per statement but has no line numbers.

**WebAssembly.** The C solver compiled with Clang 21 for `wasm32-wasi` and run in Node 24. `countdown-wasm/` builds `../countdown-c/solver.c` unchanged, with a small `compat/immintrin.h` supplying portable versions of the three x86 intrinsics, so the two can never drift. It runs at about 1.24 times native C. The one change that mattered (6%) was rounding the reciprocal quotient by adding 1.5 × 2^52 and taking the low 32 bits, because `(int)rint(x)` becomes a saturating conversion that V8 compiles with range checks. `-msimd128`, other CPU levels and `wasm-opt -O3` gained nothing measurable. The straight port is 2.1 times its native build: about half its time is wasi-libc's `qsort` calling the comparison function through `call_indirect`, and a fifth is V8 handling the variable-length `memory.copy` behind `realloc` out of line. In the same V8, the WebAssembly build is 3.3 times faster than the hand-optimised JavaScript, because it has 64-bit integers, `popcnt`, fixed types and Clang's optimisation.

**F#.** The optimised version ports the C# design: `NativeMemory` buffers through `NativePtr`, a state class with mutable fields, inline emit, rank sort and branchless search. The biggest gain (0.032 to 0.0275 ms) came from converting between integers and doubles through signed `int64`, because x86-64 has no unsigned 64-bit conversion before AVX-512 and the JIT emits a branching sequence, and from an arithmetic mask in place of an `if` the JIT kept as a branch. A mutable local captured by a closure silently becomes a heap cell, and a non-inline function returning a tuple allocates it. The straight port is 1.75 times slower than C#'s: 15% of its time is runtime type tests and F#'s generic structural comparison of tuples, and `option` allocates for every `Some`. `perf` shows JIT method names only with `DOTNET_PerfMapEnabled=1` and `DOTNET_EnableWriteXorExecute=0`.

**Kotlin.** A port of the optimised Java (`LongArray` entries, `java.lang.Long.bitCount` rank sort, inlined emit) that compiles to almost the same bytecode and runs at the same speed. Its straight port runs at 0.149 ms, the same as Java's re-timed straight port.

**Haskell.** GHC 9.10.3 with `-O2 -msse4.2`. The straight port is pure and idiomatic, with a `Data.IntMap` per subset. The optimised version runs in `ST` over unboxed `PrimArray`s with strict loops, the bitset and rank sort (`-msse4.2` makes `popCount` one instruction), the reciprocal test, split pair loops and a branchless search, and it stores values only, rebuilding origins for the answer. Two-thirds of the time is in GHC's unboxed worker `$wsolve` and garbage collection takes under 5%. It executes 1.84 times C's instructions with twice C's branch mispredictions, probably because GHC's native code generator emits branches where Clang uses conditional moves. The harness forces every answer inside the timed region so laziness cannot move the work out of it.

**OCaml.** OCaml 5.4.0 without flambda, built with `-unsafe -inline 200`. OCaml has no population count, so the bitset is a byte per 8 values and the rank sort became a radix sort with 9-bit digits. Polymorphic `max` and `min` were calling the runtime's generic comparison in the hot loops, and allocating the radix counts on every sort was costly; fixing both took it from 0.075 to 0.057 ms. The garbage collector was marking the large integer arrays (about 20% of the time) until they moved to `Bigarray`s (3%). It runs at 4.0 instructions per cycle, the best of any solver, but executes 3.4 times C's instructions, mostly tag-bit arithmetic and the radix sort.

**Common Lisp.** SBCL 2.6.0, a direct port of the optimised C with `(unsigned-byte 32/64)` arrays in a struct, `logcount` for the rank sort and `(speed 3) (safety 0)` with full type declarations; SBCL's compiler notes show no generic arithmetic left in the hot loops. It mispredicts branches about as rarely as C, which is why it beats the Rust solver. 11–15% of its time is SBCL's allocator zeroing fresh memory, because each solve allocates its arrays afresh. A `(safety 3)` build gave identical answers. The saved executable is 34 MB but starts in about 1.5 ms.

**Ruby.** Ruby 3.3.8, written like the Lua version: a Hash per subset from value to packed origin, a sorted key list, and split pair loops. `h[v] = o unless h.key?(v)` beat `h[v] ||= o`, and unrolling the whole-pool pass into the same split loops removed 21% of the time that the rare closest rounds took. Stamping values in an Array instead of a Hash was 12% slower. It beats Lua 5.4 mainly in sorting: Lua's `table.sort` spends 21% of Lua's time in the general `lua_geti`, `lua_seti` and `lua_compare` calls, while Ruby sorts integers in C with a fast path. Ubuntu's Ruby has no YJIT; the experimental RJIT (removed in Ruby 3.4) is about 1.7 times faster. Ruby builds per-size subset and split tables once when the file loads; they depend only on the pool size, like the COBOL and Forth tables.

**Julia.** Julia 1.13.1 with `-O3`. The optimised version stores values only and lists each subset's values straight out of the bitset with `trailing_zeros`, so the bitset is the sorted list and there is no rank sort; Julia executes fewer instructions than C (276k against 324k per round) but mispredicts more (1,400 against 795). The biggest gain came from forcing conditional moves: LLVM turned `ifelse(q * y == x, q, 0)` and the mask form back into a mispredicted branch, and only a tiny `llvmcall` `select` marked `!unpredictable` kept the `cmov` (132k to 115k cycles). Rounding the reciprocal quotient with `muladd(x, inv, 1.5 * 2^52)` and a `reinterpret` saved another 5%. Whole-program time is the largest gap of any CPU language: 87 ms of runtime start-up plus about 340 ms compiling `solve` on its first call; a precompiled package brings it to 235 ms.

**Erlang.** OTP 27 with the BeamAsm JIT, one scheduler (`+S 1`). Data is immutable, so each subset keeps a sorted list for scanning and a tuple for binary search with `element/2`, duplicates are removed with one `lists:usort` per subset and origins are rebuilt for the answer. Mutable options lost: an `atomics` bitset was slower than `usort` because every access is a BIF call, and ETS, maps and the process dictionary were slower still. Removing intermediate lists and `++` took it from 0.310 to 0.215 ms, and deferring the five-number subsets (searching into them instead of building them) took it to about 0.16 ms. C rejected that deferral, but on BEAM each built value costs 50–80 ns against a few in C, so the trade flips. `+S 1 -mode minimal` cut whole-program time from 115 to 85 ms, because the VM otherwise starts 32 schedulers. It was then rewritten to Elixir's design, taking it from 0.162 to 0.0575 ms, level with Elixir. Measured on an efficiency core by taking each idea back out of the final version: deferring the four-number subsets as well was the largest single gain (0.149 ms without it, against 0.085), the outward search for closest rounds was worth 24%, subset tables written into the source as constants about 19%, and stopping at the first matching partner about 17%. The old build, with a separate list per operator, measured 0.093 against 0.085 for Elixir's single list, so nothing in Elixir's design was slower in Erlang.

**Elixir.** Elixir 1.18 on the same BEAM, written independently of the Erlang version. Storing values only took it from 0.73 to 0.22 ms; deferring the five-number subsets to 0.177; constant split tables and a range check before each binary search to 0.129; deferring the four-number subsets as well, which PyTorch found 30% slower, to 0.084; checking partners in ascending order and stopping at the first hit to 0.074; and searching outward from the target (t ± 1, t ± 2, … up to 8) before building everything for the 2% of rounds that miss, which had taken 38% of the time, to 0.057. The gap to Erlang is design, not language. A map from `maps:from_keys` was 2.5 times slower than `:lists.usort`, and a packed binary for binary search 38% slower than a tuple. The `countdown` wrapper starts `erl` directly because the `elixir` launcher added 60 ms.

## Tried and rejected

- Peeling the edge cases out of C's pair loop: fewer instructions but more mispredicted branches.
- Radix sort instead of the bitset rank sort in C, at any sparsity threshold.
- Clearing the bitset during C's rank pass: the larger rank array cost more than the pass it saved.
- Profile-guided optimisation for C, Go and Fortran: at most 3%, not worth a two-stage build.
- Omitting the frame pointer in Zig.
- An FFI bitset for LuaJIT.
- Quicksort instead of radix sort on LuaJIT.
- Checking the six-number answers by recursive searches instead of building five-number subsets: far more lookups than building.
- A SIMD rewrite of the assembly.
- Sorting JavaScript values with the native `Float64Array` sort on packed keys: 60% slower than the rank sort.
- CUDA: reading a hash slot before claiming it with compare-and-swap (4% slower), 256 or 384 threads per block instead of 512 (no better), and plain lists with duplicates for five-number subsets (they would make the whole-pool pass four times longer).
- PyTorch: removing duplicates with a hash table (atomic minimum per slot, retrying collisions) and sorting only the survivors was 20% slower than sorting every result; deferring four-number subsets as well as five was 30% slower because of the nested searches.
- .NET runtime settings (tiered compilation, dynamic PGO, ReadyToRun) and GNAT `-funroll-loops` or `-gnatN`: no clear change.

## Toolchains

Clang 21.1.8, GCC 15.2.0, Rust 1.99.0, Zig 0.17.0, Go 1.25.0, gfortran 15.2.0, GNAT 14, Free Pascal 3.2.2, GnuCOBOL 3.2.0, OpenJDK 25.0.4, .NET SDK 10.0.112, Swift 6.1.3, Node 24.12.0, CUDA 12.4 with cudarc 0.19, PyTorch 2.14.1 with CUDA 13.0 and Triton 3.8, LuaJIT 2.1, Lua 5.4.8, Gforth 0.7.3, Python 3.14.4, FreeBASIC 1.10.1, bwBASIC 2.20pl2, GHC 9.10.3, OCaml 5.4.0, SBCL 2.6.0, F# on .NET SDK 10.0.112, Kotlin 2.4.21, Ruby 3.3.8, wasi-libc with wasm-ld 21, Julia 1.13.1, Erlang/OTP 27, Elixir 1.18.3.
