#!/bin/bash
# Prove every miss of every pool in all three modes, resuming from any rows already written
set -u
cd "$(dirname "$0")"
TMP=${TMP_DIR:-$HOME/.cache/countdown-sat}
mkdir -p "$TMP" results
for mode in standard cats nasty; do
    python3 run_cnf.py "jobs/full_$mode.tsv" "results/full_$mode.tsv" --workers 12 --cpus 12-31 \
        --slice satrun.slice --tmp "$TMP/$mode"
done
echo "all modes done"
