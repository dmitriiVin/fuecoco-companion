#!/bin/sh
# Run in an otherwise idle build environment.
set -eu
root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export XDG_CACHE_HOME="$tmp/cache"
cc "$root/tests/core.c" "$root/shared/motion.c" -lm -o "$tmp/motion"
cc "$root/tests/builds.c" -o "$tmp/probe"
"$tmp/motion"
"$tmp/probe"
if PROBE_ONLY=1 "$tmp/probe"; then echo 'Another build is already active' >&2; exit 1; fi
printf 'all:\n\t@sleep 3\n' > "$tmp/Makefile"
make -s -C "$tmp" &
build_pid=$!
sleep 1
PROBE_ONLY=1 "$tmp/probe"
wait "$build_pid"
if PROBE_ONLY=1 "$tmp/probe"; then echo 'Build did not clear' >&2; exit 1; fi
"$root/scripts/fuecoco-build" true
PROBE_ONLY=1 "$tmp/probe"
result=0
"$root/scripts/fuecoco-build" sh -c 'exit 7' || result=$?
test "$result" = 7 && test -f "$XDG_CACHE_HOME/fuecoco/last-error"
echo 'Observed real make from start to finish and preserved custom command exit status'
