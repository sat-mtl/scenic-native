#!/bin/sh
# Protocol / node-catalog conformance. Headless, no GPU, no hardware.
#
#   schema — every recipe's settings object against the key set score's C++
#            reader actually consumes (a missing key is a silently wrong value,
#            an extra key is a typo that does nothing), address conventions per
#            protocol, GStreamer pipeline invariants, field well-formedness.
#   graph  — routing rules against a live graph: the 8-input mixer limit and slot
#            reuse, media-type gating, fan-out cleanup, reconfigure keeping cables.
#   create — instantiate every non-enumerated recipe in the engine and assert
#            hub/device/process came up and nothing survives removal. This is
#            what catches a settings object score cannot digest: such a recipe
#            aborts the process, so the DONE marker never appears.
#
# Whether the assertions passed is judged by the [proto] DONE marker, which is
# printed only when zero assertions failed; the exit status is judged separately
# by classify_exit (tools/lib-exit.sh).
#   SCENIC_PROTO_SCENARIOS  which of the three to run (default: all)
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.." || exit 1

. "$HERE/lib-exit.sh"

. tools/env.sh
require_score
# Which scenarios to run. `create` instantiates every recipe for real, so it
# needs the NDI/LTC addons and the GStreamer runtime; an engine built without
# them can still run `schema` and `graph`.
SCENARIOS="${SCENIC_PROTO_SCENARIOS:-schema create graph}"
FAIL=0

run() {  # $1 = scenario
    scen=$1
    log="/tmp/scenic-proto-$scen.log"
    rm -f "$HOME/.config/ossia/failsafe.bit"
    since=$(now_epoch)
    env QML_IMPORT_PATH="$PWD/qml" QML2_IMPORT_PATH="$PWD/qml" SCENIC_PROTO="$scen" \
        timeout 180 "$SCORE_BIN" --ui tools/protocol-test.qml --no-restore \
        -platform offscreen > "$log" 2>&1
    code=$?
    classify_exit "$code" "$since" "$scen" || FAIL=1
    if grep -q "\[proto\] DONE" "$log" && ! grep -q "\[proto\] FAIL" "$log"; then
        grep -oE "checked .* assertions.*" "$log" | tail -1 | sed "s/^/  $scen: OK /"
    else
        echo "  $scen: FAIL"
        grep "\[proto\] FAIL" "$log" | sed 's/^Debug: //;s/ (protocol-test.*//' \
            | head -20 | sed 's/^/    /'
        # no DONE and no FAIL means the process died mid-sweep: that is the
        # settings-abort this suite exists to catch, so say so explicitly.
        if ! grep -q "\[proto\]" "$log"; then
            echo "    (no markers at all: the app did not start)"
        elif ! grep -q "\[proto\] DONE" "$log" && ! grep -q "\[proto\] FAIL" "$log"; then
            echo "    (died mid-run after: $(grep '\[proto\]' "$log" | tail -1 \
                 | sed 's/^Debug: //;s/ (protocol-test.*//'))"
        fi
        FAIL=1
    fi
}

echo "== protocol conformance =="
for scenario in $SCENARIOS; do
    run "$scenario"
done

echo "----"
[ "$FAIL" = 0 ] && echo "test-protocols: ALL PASS" || echo "test-protocols: FAILURES"
exit $FAIL
