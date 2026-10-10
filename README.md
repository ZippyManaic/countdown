# Countdown numbers solver in many languages

Solvers for the numbers round of the television game *Countdown*: six numbers, a target from 100 to 999, and the four arithmetic operations. Every implementation must print **byte-identical** answers, so the problem is defined down to which of several equally good expressions wins and how it is bracketed.

- [`paper/countdown.pdf`](paper/countdown.pdf) defines the problem formally, proves the algorithms correct and analyses the results.
- [`PERFORMANCE.md`](PERFORMANCE.md) has the timings, the per-round parallel results, what each solution cost to build and run, and notes on every language.

## Implementations

Each `countdown-<language>/` directory holds a solver, a program that deals and solves one random round, and tests.

| Group | Languages |
|---|---|
| Native | C, C++, ISPC (SIMD lanes), Rust, Zig, Go, Fortran, Ada, Pascal, Swift, Haskell, OCaml, Common Lisp, FreeBASIC, COBOL, x86-64 assembly |
| Managed and JIT | Java, Kotlin, C#, F#, JavaScript, WebAssembly, Julia, Erlang, Elixir, LuaJIT |
| Interpreted | Python, Ruby, Lua, Forth, line-numbered BASIC (bwBASIC) |
| GPU and other | Rust + CUDA, PyTorch, a precomputed lookup table, a transformer that proposes answers |
| Parallel within one round | C, Rust, Go, Java, Julia, Erlang, Elixir (`countdown-<language>-par/`) |

`countdown.py` at the top level is the original Python version.

## Benchmarks

```sh
bench/run.sh -n 3 c rust go        # build, check against the reference answers and time each solver
bench/run.sh -n 3 --whole c        # also time the whole program, start-up included
bench/scale.sh c-par rust-par      # time the parallel solvers at 1 to 32 threads
bench/metrics.sh c rust            # clean build time and peak memory
bench/loc.py                       # lines of code
```

The benchmark set is `bench/data/rounds10k.txt`, and `bench/check.py` compares answers with `bench/data/ref10k.tsv`. Timings pin to CPU 0. The parallel solvers use CPUs 0, 2, …, 14, which suits the Intel Core i9-13900HX they were measured on. Each solver needs its own toolchain; `PERFORMANCE.md` lists the versions used.

Two large generated files are not in the repository. `make -C countdown-table answers.bin` rebuilds the lookup table, and `make -C countdown-ml train.pt` regenerates the training data. The trained model, `countdown-ml/model.pt`, is included.

`bench/agent_cost.py` estimates the Claude tokens spent writing each solution from the author's Claude Code transcripts, which are not included.
