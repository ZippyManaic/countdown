#!/bin/bash
# Run the bwBASIC harness with a solver over a file of rounds since bwBASIC takes no command-line arguments
#
# Usage: basic_harness.sh solver.bas rounds out [reps]
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
solver=$(realpath "$1")
rounds=$(realpath "$2")
out=$3
# Work beside the output with short names since bwBASIC crashes opening a path of over about 128 characters
cd "$(dirname "$out")"
ln -sf "$rounds" basic_rounds.txt
# Join the harness and solver into one program since bwBASIC has no way to include files
cat "$here/basic_harness.bas" "$solver" > basic_bench.bas
# Drop the interpreter's four-line banner
COUNTDOWN_ROUNDS=basic_rounds.txt COUNTDOWN_OUT=$(basename "$out") COUNTDOWN_REPS=${4:-1} \
    bwbasic basic_bench.bas < /dev/null | tail -n +5
rm -f basic_bench.bas basic_rounds.txt
