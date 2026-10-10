#!/bin/bash
# Build every implementation's benchmark, check its answers against the reference and time the solving
#
# Usage: bench/run.sh [-n runs] [--whole] [--set standard|cats|nasty] [language...]
# Languages: python torch table ml cuda rust asm c cpp zig go fortran pascal cobol luajit lua forth gforth js ada java csharp swift wasm fsharp kotlin ruby rubyjit lisp haskell ocaml freebasic basic rust-par rust-par1 julia erlang go-par c-par java-par elixir julia-par erlang-par elixir-par ispc
set -euo pipefail

cd "$(dirname "$0")"
BENCH=$PWD
ROOT=$(cd .. && pwd)
BUILD=$BENCH/build
DATA=$BENCH/data
RUNS=5
WHOLE=0
WHOLE_RUNS=300
SET=standard
ALL=(python torch table ml cuda rust asm c cpp zig go fortran pascal cobol luajit lua forth gforth js ada java csharp swift wasm fsharp kotlin ruby rubyjit lisp haskell ocaml freebasic basic rust-par rust-par1 julia erlang go-par c-par java-par elixir julia-par erlang-par elixir-par ispc)

while [ $# -gt 0 ]; do
    case $1 in
        -n) RUNS=$2; shift 2 ;;
        --whole) WHOLE=1; shift ;;
        --set) SET=$2; shift 2 ;;
        *) break ;;
    esac
done
LANGS=("$@")
[ ${#LANGS[@]} -eq 0 ] && LANGS=("${ALL[@]}")

# Pin to one core so runs are comparable and the scheduler cannot move work between core types
PIN=()
command -v taskset >/dev/null && PIN=(taskset -c 0)
# Give parallel solvers one hardware thread on each of the eight performance cores unless PAR_CPUS says otherwise
PAR_PIN=()
command -v taskset >/dev/null && PAR_PIN=(taskset -c "${PAR_CPUS:-0,2,4,6,8,10,12,14}")

mkdir -p "$BUILD"
export DOTNET_CLI_TELEMETRY_OPTOUT=1 DOTNET_NOLOGO=1
CFLAGS=(-O2 -march=native)

# Set CMD to the command that runs a harness as CMD rounds out reps
build() {
    local lang=$1 dir=$BUILD/$1
    mkdir -p "$dir"
    case $lang in
        python)
            CMD=(python3 "$BENCH/harness/python_harness.py" "$ROOT/countdown.py") ;;
        table)
            make -s -C "$ROOT/countdown-table" answers.bin
            CMD=(python3 "$BENCH/harness/python_harness.py" "$ROOT/countdown-table/solver.py") ;;
        cuda)
            # Build the harness as an example of the crate since examples/bench.rs links to it
            (cd "$ROOT/countdown-cuda" && cargo build -q --release --example bench)
            CMD=("$ROOT/countdown-cuda/target/release/examples/bench") ;;
        ml)
            make -s -C "$ROOT/countdown-ml" model.pt
            CMD=("$ROOT/countdown-torch/.venv/bin/python" "$BENCH/harness/torch_harness.py" "$ROOT/countdown-ml/solver.py") ;;
        torch)
            make -s -C "$ROOT/countdown-torch" .venv
            CMD=("$ROOT/countdown-torch/.venv/bin/python" "$BENCH/harness/torch_harness.py" "$ROOT/countdown-torch/solver.py") ;;
        rust)
            mkdir -p "$dir/src"
            cp "$ROOT/countdown-rs/Cargo.toml" "$dir/Cargo.toml"
            sed -i 's/^name = .*/name = "bench"/' "$dir/Cargo.toml"
            # Keep everything before the program's main and replace it with the harness
            sed -e '/^fn main() -> ExitCode {/,$d' -e '/^use std::process::ExitCode;/d' \
                "$ROOT/countdown-rs/src/main.rs" > "$dir/src/main.rs"
            cat "$BENCH/harness/rust_harness.rs" >> "$dir/src/main.rs"
            # Allow the round dealing code the harness leaves unused
            (cd "$dir" && RUSTFLAGS="-A dead_code" cargo build --release -q)
            CMD=("$dir/target/release/bench") ;;
        asm)
            as -o "$dir/solver.o" "$ROOT/countdown-asm/solver.s"
            clang "${CFLAGS[@]}" -no-pie -o "$dir/bench" "$BENCH/harness/c_harness.c" "$dir/solver.o"
            CMD=("$dir/bench") ;;
        c)
            clang "${CFLAGS[@]}" -o "$dir/bench" "$BENCH/harness/c_harness.c" "$ROOT/countdown-c/solver.c"
            CMD=("$dir/bench") ;;
        ispc)
            # Use four 64-bit lanes since removing duplicates costs per lane and the narrowest gang measured fastest
            ispc -O2 --target=avx2-i64x4 --pic --wno-perf -o "$dir/solver.o" "$ROOT/countdown-ispc/solver.ispc"
            clang "${CFLAGS[@]}" -o "$dir/bench" "$BENCH/harness/c_harness.c" "$dir/solver.o"
            CMD=("$dir/bench") ;;
        cpp)
            clang "${CFLAGS[@]}" -c -o "$dir/harness.o" "$BENCH/harness/c_harness.c"
            clang++ "${CFLAGS[@]}" -std=c++23 -o "$dir/bench" "$dir/harness.o" "$ROOT/countdown-cpp/solver.cpp"
            CMD=("$dir/bench") ;;
        zig)
            cp "$ROOT/countdown-zig/src/solver.zig" "$BENCH/harness/zig_harness.zig" "$dir/"
            (cd "$dir" && zig build-exe -OReleaseFast -mcpu=native -lc zig_harness.zig -femit-bin=bench)
            CMD=("$dir/bench") ;;
        go)
            cp "$ROOT/countdown-go/go.mod" "$ROOT/countdown-go/solver.go" "$BENCH/harness/go_harness.go" "$dir/"
            (cd "$dir" && GOAMD64=v3 go build -buildvcs=false -o bench .)
            CMD=("$dir/bench") ;;
        fortran)
            clang "${CFLAGS[@]}" -c -o "$dir/harness.o" "$BENCH/harness/c_harness.c"
            gfortran -O3 -march=native -J "$dir" -c -o "$dir/solver.o" "$ROOT/countdown-fortran/solver.f90"
            gfortran -o "$dir/bench" "$dir/harness.o" "$dir/solver.o"
            CMD=("$dir/bench") ;;
        pascal)
            fpc -O3 -CpCOREAVX2 -OpCOREAVX2 -Fu"$ROOT/countdown-pascal" -FU"$dir" -o"$dir/bench" \
                "$BENCH/harness/pascal_harness.pas" >/dev/null
            CMD=("$dir/bench") ;;
        cobol)
            (cd "$dir" && cobc -x -O2 -free -o bench "$BENCH/harness/cobol_harness.c" \
                "$ROOT/countdown-cobol/solver.cob" 2>/dev/null)
            CMD=("$dir/bench") ;;
        luajit)
            CMD=(luajit "$BENCH/harness/lua_harness.lua" "$ROOT/countdown-lua") ;;
        lua)
            CMD=(lua5.4 "$BENCH/harness/lua_harness.lua" "$ROOT/countdown-lua") ;;
        forth)
            CMD=(gforth-fast "$BENCH/harness/forth_harness.fs" "$ROOT/countdown-forth") ;;
        gforth)
            CMD=(gforth "$BENCH/harness/forth_harness.fs" "$ROOT/countdown-forth") ;;
        js)
            CMD=(node "$BENCH/harness/js_harness.mjs" "$ROOT/countdown-js/solver.mjs") ;;
        swift)
            # Name the harness main.swift since Swift only allows top-level code in that file
            cp "$BENCH/harness/swift_harness.swift" "$dir/main.swift"
            swiftc -Ounchecked -wmo -module-name Bench -o "$dir/bench" "$ROOT/countdown-swift/Sources/Solver/Solver.swift" "$dir/main.swift"
            CMD=("$dir/bench") ;;
        csharp)
            dotnet build -c Release --nologo -v q "$BENCH/harness/csharp" --artifacts-path "$dir" >/dev/null
            CMD=("$dir/bin/CsHarness/release/CsHarness") ;;
        java)
            javac -d "$dir" "$ROOT"/countdown-java/src/countdown/*.java "$BENCH/harness/JavaHarness.java"
            CMD=(java -cp "$dir" JavaHarness) ;;
        ada)
            (cd "$dir" && gnatmake -q -O3 -gnatn -gnatp -march=native -aI"$ROOT/countdown-ada" -D . "$BENCH/harness/ada_harness.adb" -o bench)
            CMD=("$dir/bench") ;;
        wasm)
            make -s -C "$ROOT/countdown-wasm" solver.wasm
            CMD=(node "$BENCH/harness/wasm_harness.mjs" "$ROOT/countdown-wasm/solver.wasm") ;;
        fsharp)
            dotnet build -c Release --nologo -v q "$BENCH/harness/fsharp" --artifacts-path "$dir" >/dev/null
            CMD=("$dir/bin/FsHarness/release/FsHarness") ;;
        kotlin)
            kotlinc "$ROOT"/countdown-kotlin/src/countdown/Solver.kt "$BENCH/harness/KotlinHarness.kt" -include-runtime -d "$dir/bench.jar" 2>/dev/null
            CMD=(java -cp "$dir/bench.jar" KotlinHarnessKt) ;;
        ruby)
            CMD=(ruby "$BENCH/harness/ruby_harness.rb" "$ROOT/countdown-ruby/solver.rb") ;;
        rubyjit)
            CMD=(ruby --rjit "$BENCH/harness/ruby_harness.rb" "$ROOT/countdown-ruby/solver.rb") ;;
        lisp)
            sbcl --noinform --non-interactive --load "$ROOT/countdown-lisp/solver.lisp" --load "$BENCH/harness/lisp_harness.lisp" \
                --eval "(sb-ext:save-lisp-and-die \"$dir/bench\" :executable t :toplevel (lambda () (countdown-harness:main) (sb-ext:exit)))" >/dev/null
            CMD=("$dir/bench") ;;
        haskell)
            ghc -O2 -msse4.2 -i"$ROOT/countdown-haskell" -outputdir "$dir" -o "$dir/bench" "$BENCH/harness/haskell_harness.hs" >/dev/null
            CMD=("$dir/bench") ;;
        ocaml)
            cp "$ROOT/countdown-ocaml/solver.ml" "$BENCH/harness/ocaml_harness.ml" "$dir/"
            (cd "$dir" && ocamlfind ocamlopt -unsafe -inline 200 -package unix -linkpkg solver.ml ocaml_harness.ml -o bench)
            CMD=("$dir/bench") ;;
        freebasic)
            fbc -gen gcc -O 3 -Wc -march=native -i "$ROOT/countdown-freebasic" "$BENCH/harness/freebasic_harness.bas" -x "$dir/bench" >/dev/null
            CMD=("$dir/bench") ;;
        basic)
            CMD=(bash "$BENCH/harness/basic_harness.sh" "$ROOT/countdown-basic/solver.bas") ;;
        rust-par)
            (cd "$ROOT/countdown-rs-par" && cargo build --release -q)
            CMD=("$ROOT/countdown-rs-par/target/release/bench") ;;
        rust-par1)
            (cd "$ROOT/countdown-rs-par" && cargo build --release -q)
            CMD=(env COUNTDOWN_THREADS=1 "$ROOT/countdown-rs-par/target/release/bench") ;;
        julia)
            CMD=(julia -O3 --startup-file=no "$BENCH/harness/julia_harness.jl" "$ROOT/countdown-julia/solver.jl") ;;
        erlang)
            erlc -o "$dir" "$ROOT/countdown-erlang/solver.erl" "$BENCH/harness/erlang_harness.erl"
            CMD=(erl -noshell +S 1 -pa "$dir" -run erlang_harness main) ;;
        go-par)
            cp "$ROOT/countdown-go-par/go.mod" "$ROOT/countdown-go-par/solver.go" "$ROOT/countdown-go-par/pool.go" "$BENCH/harness/go_par_harness.go" "$dir/"
            (cd "$dir" && GOAMD64=v3 go build -buildvcs=false -o bench .)
            CMD=(env COUNTDOWN_THREADS="${COUNTDOWN_THREADS:-8}" "$dir/bench") ;;
        c-par)
            clang "${CFLAGS[@]}" -o "$dir/bench" "$BENCH/harness/c_harness.c" "$ROOT/countdown-c-par/solver.c" -pthread
            CMD=(env COUNTDOWN_THREADS="${COUNTDOWN_THREADS:-8}" "$dir/bench") ;;
        java-par)
            javac -d "$dir" "$ROOT"/countdown-java-par/src/countdownpar/*.java "$BENCH/harness/JavaParHarness.java"
            CMD=(java -cp "$dir" JavaParHarness) ;;
        elixir)
            CMD=(elixir --erl "+S 1" "$BENCH/harness/elixir_harness.exs" "$ROOT/countdown-elixir/solver.ex") ;;
        julia-par)
            CMD=(env COUNTDOWN_THREADS="${COUNTDOWN_THREADS:-8}" julia -O3 --startup-file=no -t "${COUNTDOWN_THREADS:-8},0" "$BENCH/harness/julia_par_harness.jl" "$ROOT/countdown-julia-par/solver.jl") ;;
        erlang-par)
            erlc -o "$dir" "$ROOT/countdown-erlang-par/solver_par.erl" "$BENCH/harness/erlang_par_harness.erl"
            CMD=(erl -noshell +S "${COUNTDOWN_THREADS:-8}" +sbwt very_long +swt very_low +scl false +sbt db -pa "$dir" -run erlang_par_harness main) ;;
        elixir-par)
            CMD=(elixir --erl "+S ${COUNTDOWN_THREADS:-8} +sbwtdcpu none +sbwtdio none" "$BENCH/harness/elixir_par_harness.exs" "$ROOT/countdown-elixir-par/solver.ex") ;;
        *)
            echo "unknown language $lang" >&2; exit 2 ;;
    esac
}

# Set WHOLE_CMD to the command that deals and solves one round with the language's own program
whole_command() {
    case $1 in
        python) WHOLE_CMD=(python3 "$ROOT/countdown.py") ;;
        cuda) (cd "$ROOT/countdown-cuda" && cargo build -q --release); WHOLE_CMD=("$ROOT/countdown-cuda/target/release/countdown") ;;
        ml) WHOLE_CMD=("$ROOT/countdown-torch/.venv/bin/python" "$ROOT/countdown-ml/countdown.py") ;;
        table) WHOLE_CMD=(python3 "$ROOT/countdown-table/countdown.py") ;;
        torch) WHOLE_CMD=("$ROOT/countdown-torch/.venv/bin/python" "$ROOT/countdown-torch/countdown.py") ;;
        rust) (cd "$ROOT/countdown-rs" && cargo build --release -q 2>/dev/null); WHOLE_CMD=("$ROOT/countdown-rs/target/release/countdown") ;;
        asm|c|cpp|fortran|pascal|cobol|ispc) make -s -C "$ROOT/countdown-$1" >/dev/null 2>&1; WHOLE_CMD=("$ROOT/countdown-$1/countdown") ;;
        go) make -s -C "$ROOT/countdown-go" >/dev/null; WHOLE_CMD=("$ROOT/countdown-go/countdown") ;;
        zig) (cd "$ROOT/countdown-zig" && zig build -Doptimize=ReleaseFast); WHOLE_CMD=("$ROOT/countdown-zig/zig-out/bin/countdown") ;;
        luajit) WHOLE_CMD=(luajit "$ROOT/countdown-lua/countdown.lua") ;;
        lua) WHOLE_CMD=(lua5.4 "$ROOT/countdown-lua/countdown.lua") ;;
        forth) WHOLE_CMD=(gforth-fast "$ROOT/countdown-forth/countdown.fs") ;;
        gforth) WHOLE_CMD=(gforth "$ROOT/countdown-forth/countdown.fs") ;;
        js) WHOLE_CMD=(node "$ROOT/countdown-js/countdown.mjs") ;;
        swift) (cd "$ROOT/countdown-swift" && swift build -c release >/dev/null 2>&1); WHOLE_CMD=("$ROOT/countdown-swift/.build/release/countdown") ;;
        csharp) make -s -C "$ROOT/countdown-csharp" build >/dev/null; WHOLE_CMD=("$ROOT/countdown-csharp/Countdown/bin/Release/net10.0/Countdown") ;;
        java) make -s -C "$ROOT/countdown-java" build >/dev/null; WHOLE_CMD=(java -cp "$ROOT/countdown-java/out" countdown.Countdown) ;;
        ada) make -s -C "$ROOT/countdown-ada" >/dev/null; WHOLE_CMD=("$ROOT/countdown-ada/countdown") ;;
        wasm) make -s -C "$ROOT/countdown-wasm" solver.wasm >/dev/null; WHOLE_CMD=(node "$ROOT/countdown-wasm/countdown.mjs") ;;
        fsharp) make -s -C "$ROOT/countdown-fsharp" build >/dev/null; WHOLE_CMD=("$ROOT/countdown-fsharp/Countdown/bin/Release/net10.0/Countdown") ;;
        kotlin) make -s -C "$ROOT/countdown-kotlin" build >/dev/null 2>&1; WHOLE_CMD=(java -cp "$ROOT/countdown-kotlin/countdown.jar" countdown.CountdownKt) ;;
        ruby|rubyjit) WHOLE_CMD=(ruby "$ROOT/countdown-ruby/countdown.rb") ;;
        lisp) make -s -C "$ROOT/countdown-lisp" >/dev/null 2>&1; WHOLE_CMD=("$ROOT/countdown-lisp/countdown") ;;
        rust-par|rust-par1) (cd "$ROOT/countdown-rs-par" && cargo build --release -q); WHOLE_CMD=("$ROOT/countdown-rs-par/target/release/countdown") ;;
        erlang) make -s -C "$ROOT/countdown-erlang" >/dev/null; WHOLE_CMD=("$ROOT/countdown-erlang/countdown") ;;
        go-par) make -s -C "$ROOT/countdown-go-par" >/dev/null; WHOLE_CMD=(env COUNTDOWN_THREADS="${COUNTDOWN_THREADS:-8}" "$ROOT/countdown-go-par/countdown") ;;
        c-par) make -s -C "$ROOT/countdown-c-par" >/dev/null; WHOLE_CMD=("$ROOT/countdown-c-par/countdown") ;;
        java-par) make -s -C "$ROOT/countdown-java-par" build >/dev/null; WHOLE_CMD=(java -cp "$ROOT/countdown-java-par/out" countdownpar.Countdown) ;;
        elixir) make -s -C "$ROOT/countdown-elixir" >/dev/null; WHOLE_CMD=("$ROOT/countdown-elixir/countdown") ;;
        julia-par) WHOLE_CMD=(env COUNTDOWN_THREADS="${COUNTDOWN_THREADS:-8}" julia -O3 --startup-file=no -t "${COUNTDOWN_THREADS:-8},0" "$ROOT/countdown-julia-par/countdown.jl") ;;
        erlang-par) make -s -C "$ROOT/countdown-erlang-par" >/dev/null; WHOLE_CMD=("$ROOT/countdown-erlang-par/countdown") ;;
        elixir-par) make -s -C "$ROOT/countdown-elixir-par" >/dev/null; WHOLE_CMD=("$ROOT/countdown-elixir-par/countdown") ;;
        julia) WHOLE_CMD=(julia -O3 --startup-file=no "$ROOT/countdown-julia/countdown.jl") ;;
        freebasic|basic) make -s -C "$ROOT/countdown-$1" >/dev/null; WHOLE_CMD=("$ROOT/countdown-$1/countdown") ;;
        haskell|ocaml) make -s -C "$ROOT/countdown-$1" >/dev/null; WHOLE_CMD=("$ROOT/countdown-$1/countdown") ;;
    esac
}

# Print the time per round reported by one harness run
time_run() {
    # Repeat the fastest solvers since one pass over the rounds takes only milliseconds
    local reps=1
    # Repeat the fast GPU and table runs only on the standard set since other sets fall back to slower code
    case $lang in table|cuda) [ "$SET" = standard ] && reps=20 ;; esac
    local pin=("${PIN[@]}")
    case $lang in *-par) pin=("${PAR_PIN[@]}") ;; esac
    # Stop a solver that hangs after 20 minutes so one failure cannot stall the run
    "${pin[@]}" timeout 1200 "${CMD[@]}" "$1" "$2" "$reps" 2>&1 | grep -oE '[0-9]*\.?[0-9]+ ms/round' | tail -1 | cut -d' ' -f1
}

# Stop here when another script sources this one for its build and run commands
[ "${RUN_SH_LIBRARY:-0}" = 1 ] && return 0

printf "| Language | Solve, ms per round | Checked against reference |"
[ $WHOLE -eq 1 ] && printf " Whole program, ms per run |"
printf "\n|---|---|---|"
[ $WHOLE -eq 1 ] && printf "%s" "---|"
printf "\n"

for lang in "${LANGS[@]}"; do
    build "$lang"
    # Time Python and bwBASIC once on the smaller set since the full set takes minutes per run
    # Name the cats and nasty-cats sets after their mode, leaving the standard set's names as they were
    tag=; [ "$SET" = standard ] || tag=_$SET
    rounds=$DATA/rounds${tag}10k.txt ref=$DATA/ref${tag}10k.tsv runs=$RUNS
    if [ "$lang" = python ] || [ "$lang" = basic ]; then rounds=$DATA/rounds${tag}1k.txt ref=$DATA/ref${tag}1k.tsv runs=1; fi
    out=$BUILD/$lang/answers.tsv
    best=
    for _ in $(seq "$runs"); do
        rm -f "$out"
        # Record a solver that crashes or refuses the rounds rather than stopping the whole run
        t=$(time_run "$rounds" "$out" || true)
        [ -z "$t" ] && break
        if [ -z "$best" ] || [ "$(echo "$t < $best" | bc -l)" = 1 ]; then best=$t; fi
    done
    if [ -z "$best" ]; then
        printf "| %s | failed | no answers (%s rounds) |\n" "$lang" "$(wc -l < "$rounds")"
        continue
    fi
    check=$(python3 "$BENCH/check.py" "$rounds" "$ref" "$out" || true)
    printf "| %s | %.4g | %s (%s rounds) |" "$lang" "$best" "$check" "$(wc -l < "$rounds")"
    if [ $WHOLE -eq 1 ]; then
        whole_command "$lang"
        # Pin the loop rather than each run since starting taskset every time adds about a millisecond
        # Run the PyTorch programs fewer times since loading PyTorch and starting the GPU takes seconds
        runs_whole=$WHOLE_RUNS
        case $lang in torch|ml) runs_whole=10 ;; esac
        pin=("${PIN[@]}")
        case $lang in *-par) pin=("${PAR_PIN[@]}") ;; esac
        ms=$("${pin[@]}" bash -c 'n=$1; shift; s=$(date +%s%N)
            for ((k = 0; k < n; k++)); do "$@" >/dev/null || true; done
            e=$(date +%s%N); echo "($e - $s) / 1000000 / $n" | bc -l' _ "$runs_whole" "${WHOLE_CMD[@]}")
        printf " %.2f |" "$ms"
    fi
    printf "\n"
done
