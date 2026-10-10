#!/bin/sh
# Solve every instance with countdown-c's solve() in 24 shards on CPUs 0-23 for the "main", "cats" or "nasty" pools
set -e
here=$(cd "$(dirname "$0")" && pwd)
data="$here/../data"
mode=${1:-main}
clang -O2 -march=native -std=gnu17 -o "$here/solve_all" "$here/solve_all.c" "$here/../../countdown-c/solver.c"
if [ "$mode" = cats ] || [ "$mode" = nasty ]; then
    pools="$data/pools_$mode.txt"; out="$data/c_values_$mode.bin"
    python3 -c "import sys; sys.path.insert(0, '$here/../scripts'); from common import ${mode}_pools; print('\n'.join(' '.join(map(str, p)) for p in ${mode}_pools()))" > "$pools"
else
    pools="$data/pools.txt"; out="$data/c_values.bin"
    python3 -c "import sys; sys.path.insert(0, '$here/../../countdown-table'); from pools import pools; print('\n'.join(' '.join(map(str, p)) for p in pools()))" > "$pools"
fi
shards=24
total=$(wc -l < "$pools")
for s in $(seq 0 $((shards - 1))); do
    first=$((total * s / shards)); end=$((total * (s + 1) / shards))
    # Keep the expressions only for the extra pools, whose values can lie outside the paper's 2^27 bound
    if [ "$mode" != main ]; then texts="$data/c_text$s.txt"; else texts=; fi
    taskset -c "$s" "$here/solve_all" "$pools" "$first" "$end" "$data/c_part$s.bin" $texts &
done
wait
for s in $(seq 0 $((shards - 1))); do cat "$data/c_part$s.bin"; done > "$out"
if [ "$mode" != main ]; then
    for s in $(seq 0 $((shards - 1))); do cat "$data/c_text$s.txt"; done > "${out%.bin}.txt"
fi
rm -f "$data"/c_part*.bin "$data"/c_text*.txt
ls -l "$out"
