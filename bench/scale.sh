#!/bin/bash
# Time each parallel solver at 1, 2, 4, 8, 16 and 32 threads and print a table of ms per round
#
# Usage: bench/scale.sh [-n runs] [language...]
# Languages default to every parallel solver in bench/run.sh
set -euo pipefail

cd "$(dirname "$0")"
RUNS=3
if [ "${1:-}" = -n ]; then RUNS=$2; shift 2; fi
LANGS=("$@")
[ ${#LANGS[@]} -eq 0 ] && LANGS=(c-par rust-par go-par java-par julia-par erlang-par elixir-par)

# Pair each configuration name with its thread count and the CPUs it may use
# CPUs 0-15 are the eight performance cores with two hardware threads each and 16-31 the efficiency cores
CONFIGS=(
    "1:1:0"
    "2:2:0,2"
    "4:4:0,2,4,6"
    "8:8:0,2,4,6,8,10,12,14"
    "16 (P+HT):16:0-15"
    "16 (P+E):16:0,2,4,6,8,10,12,14,16-23"
    "32:32:0-31"
)

printf "| Solver |"
for c in "${CONFIGS[@]}"; do printf " %s |" "${c%%:*}"; done
printf "\n|---|"
for _ in "${CONFIGS[@]}"; do printf -- "---|"; done
printf "\n"

for lang in "${LANGS[@]}"; do
    printf "| %s |" "$lang"
    for c in "${CONFIGS[@]}"; do
        rest=${c#*:}
        threads=${rest%%:*} cpus=${rest#*:}
        # Keep the time only when every answer matches the reference
        line=$(COUNTDOWN_THREADS=$threads PAR_CPUS=$cpus ./run.sh -n "$RUNS" "$lang" | tail -1)
        ms=$(echo "$line" | awk -F'|' '{gsub(/ /, "", $3); print $3}')
        if echo "$line" | grep -q "10000 identical, 0 ties, 0 wrong"; then
            printf " %s |" "$ms"
        else
            printf " %s (check failed) |" "$ms"
        fi
    done
    printf "\n"
done
