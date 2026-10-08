#!/bin/sh
# Camera remove-and-re-add cycle. Regression cover for a crash reproduced on
# Windows: removing a camera node left its capture graph running, so the camera
# stayed busy (the re-open produced a black source) and the stale device left a
# dangling entry in the execution state. Execution::findNode calls
# device_base::get_name() on every registered device, and get_name() is
# non-virtual over a pure virtual get_root_node(), so one destroyed entry aborts
# the process -- deterministically, not as a race.
#
# Judged on the [cycle] DONE marker. A crash stops the trace at the step it died
# on, which is what distinguishes this from a plain timeout.
#
# Needs a real camera. Reports SKIP where there is none, so CI runners pass.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.." || exit 1

. "$HERE/lib-exit.sh"
. tools/env.sh
require_score

if ! test_display; then
    echo "test-camera-cycle: SKIP (no display)"
    exit 0
fi

RUNS=${SCENIC_CYCLE_RUNS:-3}
FAIL=0
note() { echo "test-camera-cycle: $*"; }

i=1
while [ "$i" -le "$RUNS" ]; do
    LOG=/tmp/scenic-camera-cycle-$i.trace
    OUT=/tmp/scenic-camera-cycle-$i.log
    : > "$LOG"
    rm -f "$HOME/.config/ossia/failsafe.bit"
    SINCE=$(now_epoch)

    env QML_IMPORT_PATH="$PWD/qml" QML2_IMPORT_PATH="$PWD/qml" \
        SCENIC_SCENARIO="$PWD/tools/scenarios/camera-cycle.qml" \
        SCENIC_CYCLE_LOG="$LOG" SCENIC_NO_THUMBS=1 \
        timeout 60 "$SCORE_BIN" --ui qml/Main.qml --no-restore \
        > "$OUT" 2>&1
    RC=$?

    if grep -q NOCAM "$LOG"; then
        note "SKIP (no camera with two resolutions)"
        exit 0
    fi

    if grep -q DONE "$LOG"; then
        note "PASS run $i (survived $(grep -c '^open ' "$LOG") opens)"
    else
        note "FAIL run $i: died at '$(tail -1 "$LOG")' rc=$RC"
        classify_exit "$RC" "$SINCE" || true
        FAIL=1
    fi

    # The leak shows up as the camera staying busy, which is visible before any
    # crash is: worth reporting even on a run that survives.
    if grep -qiE "device already in use|Could not run graph|I/O error" "$OUT"; then
        note "FAIL run $i: capture not released (device busy on re-open)"
        FAIL=1
    fi

    i=$((i + 1))
done

exit "$FAIL"
