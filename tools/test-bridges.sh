#!/bin/sh
# Data-bridge tests (BridgeStore): the transport/codec plane, over real
# sockets. Headless, no GPU, no hardware — a MIDI port is used when the machine
# has one and that leg is skipped when it does not.
#
#   SCENIC_BRIDGE_SCENARIOS  which scenarios to run (default: all)
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.." || exit 1

. "$HERE/lib-exit.sh"

. tools/env.sh
require_score
SCENARIOS="${SCENIC_BRIDGE_SCENARIOS:-codec route session undo matrix streams}"
FAIL=0

for scen in $SCENARIOS; do
    rm -f "$HOME/.config/ossia/failsafe.bit"
    since=$(now_epoch)
    log="/tmp/scenic-bridge-$scen.log"
    env QML_IMPORT_PATH="$PWD/qml" QML2_IMPORT_PATH="$PWD/qml" SCENIC_BRIDGE="$scen" \
        timeout 90 "$SCORE_BIN" --ui tools/bridge-test.qml --no-restore \
        -platform offscreen > "$log" 2>&1
    code=$?
    # Marker-judged: "[bridge] DONE" is printed only when no check failed.
    if grep -q "\[bridge\] DONE" "$log" && ! grep -q "\[bridge\] FAIL" "$log"; then
        echo "  $scen: OK ($(grep -oE 'DONE [0-9]+ checks' "$log" | tail -1))"
    else
        echo "  $scen: FAIL"
        grep "\[bridge\] FAIL" "$log" | sed 's/^/    /'
        FAIL=1
    fi
    classify_exit "$code" "$since" "$scen" || FAIL=1
done

echo "----"
[ "$FAIL" = 0 ] && echo "test-bridges: ALL PASS" || echo "test-bridges: FAILURES"
exit $FAIL
