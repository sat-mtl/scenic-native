#!/bin/sh
# Headless structural tests (no GPU / no display): catalog integrity, a seeded
# model fuzzer with invariant checks, and session round-trip. Runs under
# -platform offscreen so it is safe in CI.
#
#   SCENIC_FUZZ_SEEDS  space-separated seeds (default: a fixed set)
#   SCENIC_FUZZ_OPS    ops per fuzz run (default 120)
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.." || exit 1

. "$HERE/lib-exit.sh"

. tools/env.sh
require_score
SEEDS="${SCENIC_FUZZ_SEEDS:-1 2 3 7 13 42 99}"
OPS="${SCENIC_FUZZ_OPS:-120}"
FAIL=0

# set by run(); the caller classifies them with classify_exit
LAST_CODE=0
LAST_SINCE=0

run() {  # $1 = scenario, rest = extra env
    scen=$1; shift
    rm -f "$HOME/.config/ossia/failsafe.bit"
    LAST_SINCE=$(now_epoch)
    env QML_IMPORT_PATH="$PWD/qml" QML2_IMPORT_PATH="$PWD/qml" SCENIC_STRESS="$scen" "$@" \
        timeout 60 "$SCORE_BIN" --ui tools/stress-test.qml --no-restore -platform offscreen \
        > "/tmp/scenic-stress-$scen.log" 2>&1
    LAST_CODE=$?
    # Whether the scenario's assertions passed is judged by its markers, not by
    # the exit code: "[stress] DONE" is printed only after every invariant and
    # the undo/redo consistency check passed, so it is a stronger success signal
    # than exit==0. The exit status is judged on its own, by classify_exit.
    log="/tmp/scenic-stress-$scen.log"
    grep -q "\[stress\] DONE" "$log" && ! grep -q "\[stress\] FAIL" "$log"
}

echo "== catalog integrity =="
if run catalog; then
    grep -oE "checked .*nodes.*" /tmp/scenic-stress-catalog.log | tail -1 | sed 's/^/  /'
else
    echo "  FAIL"; grep "\[stress\] FAIL" /tmp/scenic-stress-catalog.log | sed 's/^/  /'; FAIL=1
fi
classify_exit "$LAST_CODE" "$LAST_SINCE" "catalog" || FAIL=1

echo "== model fuzz (seeds: $SEEDS, $OPS ops) =="
for s in $SEEDS; do
    if run fuzz SCENIC_FUZZ_SEED="$s" SCENIC_FUZZ_OPS="$OPS"; then
        echo "  seed $s: OK ($(grep -oE 'survived .* ops' /tmp/scenic-stress-fuzz.log | tail -1))"
    else
        echo "  seed $s: FAIL"
        grep "\[stress\]" /tmp/scenic-stress-fuzz.log | tail -3 | sed 's/^/    /'
        FAIL=1
    fi
    classify_exit "$LAST_CODE" "$LAST_SINCE" "seed $s" || FAIL=1
done

# SCENIC_FUZZ_SAFE excludes every op that tears a device down.
echo "== model fuzz, safe mode (no device teardown) =="
if run fuzz SCENIC_FUZZ_SAFE=1 SCENIC_FUZZ_SEED=1 SCENIC_FUZZ_OPS="$OPS"; then
    echo "  safe: OK ($(grep -oE 'survived .* ops' /tmp/scenic-stress-fuzz.log | tail -1))"
else
    echo "  safe: FAIL"
    grep "\[stress\]" /tmp/scenic-stress-fuzz.log | tail -3 | sed 's/^/    /'
    FAIL=1
fi
classify_exit "$LAST_CODE" "$LAST_SINCE" "safe" || FAIL=1

echo "== session round-trip (seeds: $SEEDS) =="
# Delete the artifact first: the graph is seed-deterministic, so a save() that
# became a no-op would otherwise round-trip against the previous run's file.
rm -f "$HOME/Documents/Scenic/sessions/stress_roundtrip.scenic.json" \
      "$HOME/Documents/Scenic/sessions/stress_roundtrip.score"
for s in $SEEDS; do
    if run session SCENIC_FUZZ_SEED="$s"; then
        :
    else
        echo "  seed $s: FAIL"
        grep "\[stress\] FAIL" /tmp/scenic-stress-session.log | sed 's/^/    /'
        FAIL=1
    fi
    classify_exit "$LAST_CODE" "$LAST_SINCE" "seed $s" || FAIL=1
done
[ "$FAIL" = 0 ] && echo "  all seeds round-tripped"

echo "----"
[ "$FAIL" = 0 ] && echo "test-stress: ALL PASS" || echo "test-stress: FAILURES"
exit $FAIL
