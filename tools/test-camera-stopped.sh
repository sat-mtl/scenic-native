#!/bin/sh
# Is the camera released when the node is removed and playback stops right
# after, before the render tick could drain the removal?
#
# unregister_node() only enqueues REMOVE_NODE; run_commands() drains that queue
# from updateGraph(), as part of rendering. So a removal still queued when the
# ticks stop is never acted on, and the capture outlives both the node and
# playback. ~GfxContext drains the queue only to release disowned nodes.
#
# Two arms, judged against the handles held before the run:
#   delay=0     stop in the same turn as the removal -- the race
#   delay=2000  a tick gets in first -- the control, which must release
# A control that leaks means the test is measuring something else, and the run
# says so rather than blaming the race.
#
# Needs a real camera. Reports SKIP where there is none.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.." || exit 1

. "$HERE/lib-exit.sh"
. tools/env.sh
require_score

if ! test_display; then
    echo "test-camera-stopped: SKIP (no display)"
    exit 0
fi

export TMPDIR="${TMPDIR:-/var/tmp}"

count_holders() {
    n=0
    for d in /dev/video*; do
        [ -e "$d" ] || continue
        h=$(fuser "$d" 2>/dev/null | wc -w)
        n=$((n + h))
    done
    echo "$n"
}

FAIL=0
SKIP_ALL=1
VOID=0

run_arm() {
    delay=$1
    label=$2
    LOG=/tmp/scenic-camera-stopped-$delay.trace
    OUT=/tmp/scenic-camera-stopped-$delay.log
    FDS=/tmp/scenic-camera-stopped-$delay.fds
    : > "$LOG"; : > "$FDS"
    rm -f "$HOME/.config/ossia/failsafe.bit"

    BASE=$(count_holders)
    SINCE=$(now_epoch)
    echo "test-camera-stopped: [$label] baseline=$BASE handle(s)"

    env QML_IMPORT_PATH="$PWD/qml" QML2_IMPORT_PATH="$PWD/qml" \
        SCENIC_SCENARIO="$PWD/tools/scenarios/camera-stopped.qml" \
        SCENIC_STOPPED_LOG="$LOG" SCENIC_STOP_DELAY="$delay" \
        SCENIC_NO_THUMBS=1 \
        timeout 90 "$SCORE_BIN" --ui qml/Main.qml --no-restore \
        > "$OUT" 2>&1 &
    APP=$!
    # The shell would otherwise print its own "Aborted" job notice over the
    # test's output; the exit status is read from wait below either way.

    while kill -0 "$APP" 2>/dev/null; do
        echo "$(tail -1 "$LOG" 2>/dev/null)|video_fds=$(count_holders)" >> "$FDS"
        sleep 1
    done
    wait "$APP"
    RC=$?

    if grep -q NOCAM "$LOG"; then
        echo "test-camera-stopped: [$label] SKIP (no camera)"
        return 0
    fi
    if [ ! -s "$LOG" ]; then
        # No marker at all: the app died before the scenario ran, which says
        # nothing about releasing a camera. Not this test's failure to report.
        echo "test-camera-stopped: [$label] VOID (app never reached the scenario) rc=$RC"
        VOID=1
        return 1
    fi
    if ! grep -q OPENED "$LOG"; then
        echo "test-camera-stopped: [$label] FAIL (scenario ran but the camera never opened) rc=$RC"
        FAIL=1
        return 1
    fi
    SKIP_ALL=0

    PEAK=$(sed -n '/OPENED/,/REMOVING/p' "$FDS" | sed 's/.*video_fds=//' | sort -rn | head -1)
    PEAK=${PEAK:-0}
    if [ "$PEAK" -le "$BASE" ]; then
        echo "test-camera-stopped: [$label] SKIP (opening the node took no handle)"
        return 0
    fi

    # Judged on the tail: the scenario deliberately stays alive for 12s past
    # the stop, so a release that never comes is visible rather than hidden by
    # the process exiting.
    AFTER=$(grep -A20 'STOPPED' "$FDS" | sed 's/.*video_fds=//' | sort -n | head -1)
    AFTER=${AFTER:-0}
    echo "test-camera-stopped: [$label] peak=$PEAK lowest-after-stop=$AFTER"

    if [ "$AFTER" -gt "$BASE" ]; then
        echo "test-camera-stopped: [$label] LEAK (camera still held after the node was removed and playback stopped)"
        FAIL=1
    else
        echo "test-camera-stopped: [$label] released"
    fi
    classify_exit "$RC" "$SINCE" "test-camera-stopped-$label" "$OUT" || FAIL=1
}

# Control first: if a tick gets in before the stop and the camera is still
# leaked, the race arm proves nothing.
run_arm 2000 control
CONTROL_FAIL=$FAIL
run_arm 0 race

if [ "$VOID" -ne 0 ]; then
    echo "test-camera-stopped: VOID (the app never reached the scenario; nothing was measured)"
    exit 1
fi
if [ "$SKIP_ALL" -eq 1 ]; then
    echo "test-camera-stopped: SKIP (no usable camera)"
    exit 0
fi
if [ "$CONTROL_FAIL" -ne 0 ]; then
    echo "test-camera-stopped: VOID (the control arm leaked too, so this says nothing about the race)"
    exit 1
fi
if [ "$FAIL" -ne 0 ]; then
    echo "test-camera-stopped: FAIL (removal racing the render-tick stop leaks the capture)"
    exit 1
fi
echo "test-camera-stopped: PASS (released even when playback stops with the removal still queued)"
exit 0
