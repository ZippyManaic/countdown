#!/bin/sh
# Check that the program accepts every mode and rejects bad arguments with exit code 2
cd "$(dirname "$0")"
failures=0

# Run the program with the given arguments and compare its exit code with the allowed codes in $want
check() {
    ./countdown "$@" >/dev/null 2>&1
    code=$?
    case " $want " in
        *" $code "*) ;;
        *) echo "FAIL: countdown $* exited with $code" >&2; failures=$((failures + 1)) ;;
    esac
}

want="0 1"
check
check standard
check standard 1
check cats
check cats 0
check nasty 4
want=2
check standard 3
check cats 5
check dogs
check cats 1 2
check cats x
if [ "$(./countdown cats 5 2>&1 >/dev/null)" != "usage: countdown [standard|cats|nasty] [LARGE]" ]; then
    echo "FAIL: usage line" >&2
    failures=$((failures + 1))
fi

[ $failures -eq 0 ] && echo "all exit code checks passed"
[ $failures -eq 0 ]
