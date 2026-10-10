#!/usr/bin/env bash
# Run every Z3 check on CPUs 16 to 19 with one memory-capped job chain per CPU
set -u
cd "$(dirname "$0")"
mkdir -p results/logs
WIDE=${WIDE:-0}
# Clear earlier shard files so a rerun with a different sharding is not double counted
rm -f results/no_solution_*.jsonl

# Run one command under a 4 GB memory cap with no swap and a wall-clock limit pinned to one CPU
capped() {
    local cpu=$1 limit=$2 log=$3
    shift 3
    systemd-run --user --scope -q -p MemoryMax=4G -p MemorySwapMax=0 \
        timeout "$limit" taskset -c "$cpu" "$@" >"results/logs/$log.log" 2>&1
    echo "cpu $cpu: $log exit $?"
}

chain16() {
    capped 16 600 lemma_validate python3 lemma_reciprocal.py validate
    capped 16 600 lemma_mutation python3 lemma_reciprocal.py mutation
    capped 16 30000 lemma_int32 python3 lemma_reciprocal.py int32 600
    capped 16 600 prop_prime python3 prop_prime.py
    capped 16 4000 cats_max python3 cats_max.py
}
chain17() {
    capped 17 20000 worst_0 python3 no_solution.py worst --shard 0 --shards 3
    capped 17 20000 t967_0 python3 no_solution.py t967 --shard 0 --shards 2
    capped 17 40000 prop_max_bound python3 prop_max_bound.py 120
}
chain18() {
    capped 18 20000 worst_1 python3 no_solution.py worst --shard 1 --shards 3
    capped 18 20000 t967_1 python3 no_solution.py t967 --shard 1 --shards 2
    capped 18 40000 cats4_0 python3 no_solution.py cats4 --shard 0 --shards 2
}
chain19() {
    capped 19 20000 worst_2 python3 no_solution.py worst --shard 2 --shards 3
    capped 19 40000 cats4_1 python3 no_solution.py cats4 --shard 1 --shards 2
    capped 19 40000 lemma_fp python3 lemma_reciprocal.py fp 600
    # Run the optional 64-bit widening which takes hours when WIDE=1
    if [ "$WIDE" = 1 ]; then capped 19 80000 lemma_wide python3 lemma_reciprocal.py wide 30 53; fi
}

chain16 & chain17 & chain18 & chain19 &
wait
python3 summarise.py
