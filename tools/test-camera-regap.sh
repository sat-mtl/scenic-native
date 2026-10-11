#!/bin/sh
# How soon after removing a camera node can the same camera be opened again?
#
# test-camera-leak.sh only shows that the handle goes away, sampled once a
# second, and both the fixed and the unfixed build satisfy that: the unfixed one
# closes the capture too, just later. renderedNodesChanged() releases the frames
# and then finds must_stop false, so the close waits on the last shared_ptr to
# the decoder -- ~VideoFrameShare posts it to qApp, and the node itself survives
# until the nursery's 100 ms QTimer fires. With must_stop set, the render thread
# closes it on the tick that drains REMOVE_NODE, about a frame.
#
# So the two differ in latency, and only a short gap between remove and re-open
# separates them. This asserts the short gap works, which is what a user doing
# the same thing by hand would hit.
#
# Each gap is run REPEATS times because camera re-open is genuinely flaky on
# some devices; a gap counts as failing only if it fails every attempt, so one
# bad run does not fail the suite.
#
# The verdict comes from the camera handles score itself holds, read out of
# /proc/<pid>/fd while the scenario runs. Two weaker signals were tried first
# and both are unusable:
#
#   - the scenario's own "opened N" marker: NodeStore.create returns an id
#     whether or not the capture opened, so it says nothing about the camera;
#   - score's "could not start the camera input" warning: in --ui mode score
#     installs no Qt message handler (SafeQApplication only installs one under
#     SCORE_DEBUG, and the Messages panel that would forward it is not loaded),
#     so no qWarning or qDebug from any plugin reaches stderr. Measured: with
#     the camera held by another process for a whole run, every open was
#     refused and the warning appeared zero times, while the test reported
#     PASS 3/3.
#
# An fd pointing at /dev/video* in score's own process is first-hand evidence
# that the capture opened, needs no cooperation from Qt, and cannot be confused
# with another process holding the camera.
#
# Needs a camera offering two modes. Reports SKIP where there is none.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.." || exit 1

. "$HERE/lib-exit.sh"
. "$HERE/lib-camera.sh"
. tools/env.sh
require_score

if ! test_display; then
    echo "test-camera-regap: SKIP (no display)"
    exit 0
fi

export TMPDIR="${TMPDIR:-/var/tmp}"
GAPS=${SCENIC_REGAP_GAPS:-"150 2000"}
# Both sequences are run: "aba" re-opens the first mode on the third round,
# "abb" does not. If only "aba" fails, the fault is re-opening a mode already
# used, not the number of opens -- and the two have different causes.
SEQS=${SCENIC_REGAP_SEQS:-"aba abb"}
REPEATS=${SCENIC_REGAP_REPEATS:-3}
FAIL=0
SAW_CAMERA=0
VOID=0

# One attempt at one gap. Echoes "<succeeded>/<attempted>", or "skip".
attempt() {
    gap=$1
    seq=$2
    try=$3
    LOG=/tmp/scenic-regap-$gap-$seq-$try.trace
    OUT=/tmp/scenic-regap-$gap-$seq-$try.log
    : > "$LOG"
    rm -f "$HOME/.config/ossia/failsafe.bit"
    SINCE=$(now_epoch)

    FDS=/tmp/scenic-regap-$gap-$seq-$try.fds
    : > "$FDS"

    env QML_IMPORT_PATH="$PWD/qml" QML2_IMPORT_PATH="$PWD/qml" \
        SCENIC_SCENARIO="$PWD/tools/scenarios/camera-regap.qml" \
        SCENIC_REGAP_LOG="$LOG" SCENIC_GAP="$gap" SCENIC_HOLD=2000 \
        SCENIC_SEQ="$seq" SCENIC_NO_THUMBS=1 \
        timeout 120 "$SCORE_BIN" --ui qml/Main.qml --no-restore \
        > "$OUT" 2>&1 &
    runner=$!

    app=$(camera_app_pid "$runner")
    # Sampled against the round the scenario is in, so a failed open is
    # attributed to its own round rather than to the run as a whole.
    sample_camera_fds "$runner" "$app" "$LOG" "$FDS"
    wait "$runner"
    RC=$?

    if grep -q NOCAM "$LOG"; then
        echo skip
        return 0
    fi
    if [ ! -s "$LOG" ]; then
        # The app never wrote a marker: it died before the scenario ran, which
        # is not a statement about re-opening a camera.
        echo void
        return 0
    fi
    # grep -c prints 0 and exits 1 with no match, so "|| echo 0" would print a
    # second zero and the arithmetic below would see "0 0".
    tried=$(grep -c '^open ' "$LOG" 2>/dev/null); tried=${tried:-0}
    # A round counts as opened only if score held a camera descriptor at some
    # point while that round was the current one.
    ok=$(camera_rounds_opened "$FDS" "$tried")
    # A crash is a failure of this gap even if the opens up to it succeeded.
    classify_exit "$RC" "$SINCE" "test-camera-regap-$gap" "$OUT" > /dev/null 2>&1 || ok=-1
    echo "$ok/$tried"
}

for gap in $GAPS; do
  for seq in $SEQS; do
    rounds=$(printf '%s' "$seq" | wc -c)
    rounds=$((rounds))
    best=0
    detail=""
    skipped=1
    voided=0
    try=1
    while [ "$try" -le "$REPEATS" ]; do
        r=$(attempt "$gap" "$seq" "$try")
        if [ "$r" = skip ]; then
            detail="$detail skip"
        elif [ "$r" = void ]; then
            detail="$detail void"
            VOID=1
            voided=1
        else
            skipped=0
            SAW_CAMERA=1
            ok=${r%/*}
            detail="$detail $r"
            [ "$ok" -gt "$best" ] && best=$ok
        fi
        try=$((try + 1))
    done
    if [ "$skipped" -eq 1 ]; then
        if [ "$voided" -eq 1 ]; then
            echo "test-camera-regap: gap=${gap}ms seq=$seq VOID (app never reached the scenario)"
        else
            echo "test-camera-regap: gap=${gap}ms seq=$seq SKIP (no camera with two modes)"
        fi
        continue
    fi
    echo "test-camera-regap: gap=${gap}ms seq=$seq best=$best/$rounds over $REPEATS attempt(s):$detail"
    if [ "$SAW_CAMERA" -eq 1 ] && [ "$best" -lt "$rounds" ]; then
        echo "test-camera-regap: gap=${gap}ms seq=$seq FAIL (no attempt completed every re-open)"
        FAIL=1
    fi
  done
done

if [ "$SAW_CAMERA" -eq 0 ]; then
    if [ "$VOID" -ne 0 ]; then
        echo "test-camera-regap: VOID (the app never reached the scenario; nothing was measured)"
        exit 1
    fi
    echo "test-camera-regap: SKIP (no usable camera)"
    exit 0
fi
if [ "$FAIL" -ne 0 ]; then
    echo "test-camera-regap: FAIL (a removed camera could not be re-opened promptly)"
    exit 1
fi
echo "test-camera-regap: PASS (re-open succeeds at every gap tested)"
exit 0
