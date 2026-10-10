#!/bin/sh
# Run a command under a hard memory cap and timeout pinned to the given CPUs so a runaway proof cannot exhaust the machine
# Usage: cap.sh MEM SECONDS CPUS command...
mem=$1 secs=$2 cpus=$3
shift 3
if systemd-run --user --scope -q -p MemoryMax="$mem" -p MemorySwapMax=0 true 2>/dev/null; then
    exec systemd-run --user --scope -q -p MemoryMax="$mem" -p MemorySwapMax=0 timeout "$secs" taskset -c "$cpus" "$@"
fi
# Fall back to an address-space limit when user scopes are unavailable
bytes=$(numfmt --from=iec "$mem")
exec prlimit --as="$bytes" timeout "$secs" taskset -c "$cpus" "$@"
