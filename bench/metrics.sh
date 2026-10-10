#!/bin/bash
# Measure each solution's clean build time and the peak memory of one pass over the benchmark rounds
#
# Usage: bench/metrics.sh [language...]
# Start each build from an empty build directory with toolchain caches warm so it times the solution and not the standard library
set -euo pipefail

cd "$(dirname "$0")"
RUN_SH_LIBRARY=1 source ./run.sh "$@"
SCRATCH=$(mktemp -d)
trap 'rm -rf "$SCRATCH"' EXIT

# Give Cargo and Go fresh build caches so earlier builds of the same code cannot be reused
prepare() {
    rm -rf "${BUILD:?}/$1"
    case $1 in
        rust|rust-par|rust-par1|cuda)
            rm -rf "$SCRATCH/cargo"
            export CARGO_TARGET_DIR=$SCRATCH/cargo ;;
        wasm)
            rm -f "$ROOT/countdown-wasm/solver.wasm" ;;
        go|go-par)
            # Build the standard library first since Go would otherwise compile it inside the timed build
            export GOCACHE=$SCRATCH/go-$1
            GOAMD64=v3 go build std ;;
    esac
}

printf "| Solution | Clean build, s | Peak memory, MB |\n|---|---|---|\n"
for lang in "${LANGS[@]}"; do
    case $lang in
        # Skip the builds that generate data or install packages rather than compile code
        table|ml|torch) build_s=– ;;
        *)
            prepare "$lang"
            start=$(date +%s%N)
            build "$lang" >/dev/null 2>&1
            end=$(date +%s%N)
            build_s=$(echo "scale=2; ($end - $start) / 1000000000" | bc)
            unset CARGO_TARGET_DIR GOCACHE ;;
    esac
    # Rebuild into the usual places so the run uses the normal binaries
    build "$lang" >/dev/null 2>&1
    case $build_s in .*) build_s=0$build_s ;; esac
    # Leave out the interpreters that need no build step
    case $lang in python|lua|luajit|forth|gforth|js|ruby|rubyjit|basic|julia|julia-par|elixir|elixir-par) build_s=– ;; esac
    rounds=$DATA/rounds10k.txt
    [ "$lang" = python ] || [ "$lang" = basic ] && rounds=$DATA/rounds1k.txt
    pin=("${PIN[@]}")
    case $lang in *-par) pin=("${PAR_PIN[@]}") ;; esac
    /usr/bin/time -o "$SCRATCH/rss" -f "%M" "${pin[@]}" "${CMD[@]}" "$rounds" "$SCRATCH/answers.tsv" 1 >/dev/null 2>&1
    kb=$(tail -1 "$SCRATCH/rss")
    printf "| %s | %s | %.1f |\n" "$lang" "$build_s" "$(echo "$kb / 1024" | bc -l)"
done
