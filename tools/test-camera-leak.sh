#!/bin/sh
# Does score still hold the camera after its node is removed?
#
# Watches the process's open /dev/video* handles while camera-leak.qml opens a
# camera node and then removes it. A handle still open after REMOVED is the leak:
# on Windows the camera is exclusive, so the next open returns a black source.
#
# Needs a real camera. Reports SKIP where there is none.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.." || exit 1

. "$HERE/lib-exit.sh"
. tools/env.sh
require_score

if ! test_display; then
    echo "test-camera-leak: SKIP (no display)"
    exit 0
fi

export TMPDIR="${TMPDIR:-/var/tmp}"
LOG=/tmp/scenic-camera-leak.trace
OUT=/tmp/scenic-camera-leak.log
FDS=/tmp/scenic-camera-leak.fds
: > "$LOG"; : > "$FDS"
rm -f "$HOME/.config/ossia/failsafe.bit"

# Anything already holding a camera -- a browser, a video call -- counts too, so
# measure it before starting and judge against it, not against zero.
count_holders() {
    n=0
    for d in /dev/video*; do
        [ -e "$d" ] || continue
        h=$(fuser "$d" 2>/dev/null | wc -w)
        n=$((n + h))
    done
    echo "$n"
}
BASE=$(count_holders)
echo "test-camera-leak: $BASE camera handle(s) held before the run"
SINCE=$(now_epoch)

env QML_IMPORT_PATH="$PWD/qml" QML2_IMPORT_PATH="$PWD/qml" \
    SCENIC_SCENARIO="$PWD/tools/scenarios/camera-leak.qml" \
    SCENIC_LEAK_LOG="$LOG" SCENIC_NO_THUMBS=1 \
    timeout 60 "$SCORE_BIN" --ui qml/Main.qml --no-restore \
    > "$OUT" 2>&1 &
APP=$!

# Sample who holds a camera alongside the scenario's own phase markers, so the
# two can be read against each other afterwards. Asked of the devices rather
# than of a pid: an AppImage may not keep the pid we started.
while kill -0 "$APP" 2>/dev/null; do
    echo "$(tail -1 "$LOG" 2>/dev/null)|video_fds=$(count_holders)" >> "$FDS"
    sleep 1
done
wait "$APP"
RC=$?

# The handle counts say nothing about how the process ended, and a crash after
# the scenario's DONE would otherwise pass unnoticed.
EXIT_BAD=0
classify_exit "$RC" "$SINCE" "test-camera-leak" "$OUT" || EXIT_BAD=1

if grep -q NOCAM "$LOG"; then
    echo "test-camera-leak: SKIP (no camera)"
    exit 0
fi
if ! grep -q OPENED "$LOG"; then
    echo "test-camera-leak: FAIL (camera never opened) rc=$RC"
    exit 1
fi

# Peak while the node existed, and what was still held two samples after REMOVED.
PEAK=$(sed -n '/OPENED/,/remove /p' "$FDS" | sed 's/.*video_fds=//' | sort -rn | head -1)
AFTER=$(grep -A4 'REMOVED' "$FDS" | sed 's/.*video_fds=//' | sort -rn | head -1)
PEAK=${PEAK:-0}; AFTER=${AFTER:-0}
echo "test-camera-leak: handles baseline=$BASE peak=$PEAK after-removal=$AFTER"

if [ "$PEAK" -le "$BASE" ]; then
    echo "test-camera-leak: SKIP (opening the node took no camera handle)"
    exit 0
fi
if [ "$AFTER" -gt "$BASE" ]; then
    echo "test-camera-leak: FAIL (camera still held after the node was removed)"
    exit 1
fi
if [ "$EXIT_BAD" -ne 0 ]; then
    echo "test-camera-leak: FAIL (camera released, but the process did not exit cleanly)"
    exit 1
fi
echo "test-camera-leak: PASS (camera released with the node)"
exit 0
