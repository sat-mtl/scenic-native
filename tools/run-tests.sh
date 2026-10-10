#!/bin/sh
# Sequential automated test suites with cleanup between runs.
# Usage: tools/run-tests.sh   (headless; suites that need a display are skipped)
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.." || exit 1

. "$HERE/lib-exit.sh"

PASS=0
FAIL=0
SKIP=0
FAILED_SUITES=""
SKIPPED_SUITES=""

# Between suites: leave nothing behind that a later suite could assert on, or
# that could keep a port bound. Only the session names the suites create
# themselves are removed, nothing else in the session folder.
cleanup() {
    "$(dirname "$0")/kill-app.sh"
    # gst fixtures from the webrtc/media suites: a leaked signalling server keeps
    # 8443 bound, and the next run then talks to the stale server's producer list
    pkill -f "gst-webrtc-signalling-server" 2>/dev/null
    pkill -f "gst-launch-1.0" 2>/dev/null
    rm -f "$HOME/.config/ossia/failsafe.bit"
    # probe artifacts: asserting on a stale one is a false pass
    rm -f /tmp/it_*.jpg /tmp/it_*.raw /tmp/scenic_probe.* /tmp/scenic_rec.mp4 \
          /tmp/scenic_ltc.raw \
          /tmp/scenic_clip.mp4 /tmp/scenic_testclip.mkv /tmp/scenic_mloop \
          /tmp/scenic-passthrough.fs /tmp/scenic-spike-processes.json
    for s in p1auto p2auto stress_roundtrip it_sessionvideo bridge_roundtrip; do
        rm -f "$HOME/Documents/Scenic/sessions/$s.scenic.json" \
              "$HOME/Documents/Scenic/sessions/$s.score"
    done
    sleep 1
}

suite() {
    name=$1; shift
    cleanup
    "$@" > "/tmp/scenic-test-$name.log" 2>&1
    code=$?
    # 77 = the suite decided it cannot run here (no display). It is counted
    # separately so that a suite that never ran is not reported as a pass.
    if [ "$code" = 0 ]; then
        echo "PASS $name"
        PASS=$((PASS+1))
    elif [ "$code" = 77 ]; then
        echo "SKIP $name ($(tail -1 "/tmp/scenic-test-$name.log"))"
        SKIP=$((SKIP+1))
        SKIPPED_SUITES="$SKIPPED_SUITES $name"
    else
        echo "FAIL $name (log: /tmp/scenic-test-$name.log)"
        FAIL=$((FAIL+1))
        FAILED_SUITES="$FAILED_SUITES $name"
    fi
}

check_done() {
    pattern=$1; shift
    # tee to stderr so suite()'s redirect still captures the output: with a bare
    # `| grep -q` the log it points to would be empty. Match with a
    # full-stream grep rather than `grep -q`, which exits on the first hit and
    # SIGPIPEs the app the instant it prints its marker, so nothing after the
    # marker ever runs.
    #
    # The app's own exit status is at the far end of a pipe; carry it out
    # through a file and classify it, so a run that prints its marker and then
    # crashes or is killed by `timeout` is not mistaken for a clean one.
    rcfile="/tmp/scenic-rc.$$"
    rm -f "$rcfile"
    since=$(now_epoch)
    { "$@" 2>&1; echo $? > "$rcfile"; } | tee /dev/stderr | grep -E "$pattern" > /dev/null
    marker=$?
    code=$(cat "$rcfile" 2>/dev/null || echo 0)
    rm -f "$rcfile"
    # propagate a suite's own "cannot run here" so suite() still reports SKIP
    [ "${code:-0}" = 77 ] && return 77
    classify_exit "${code:-0}" "$since" "exit status" || return 1
    return $marker
}

# One private display for the suites that render (see test_display). Only
# SCENIC_TEST_DISPLAY is passed on: the headless suites must see no display,
# or score picks a GL context it cannot render with.
test_display || echo "no Xvfb: the suites that render will be skipped"
unset DISPLAY

# The GStreamer registry is shared by run.sh and three suites; rebuild it once
# per run rather than trusting whatever an interrupted run left behind.
rm -f "${TMPDIR:-/tmp}/scenic-gst-sdk-registry.bin"

# --- headless suites (no display needed; safe in CI) ---
suite lint    ./tools/lint.sh
suite stress  ./tools/test-stress.sh
suite proto   ./tools/test-protocols.sh
suite bridges ./tools/test-bridges.sh
suite spike   check_done "spike\] AUTO DONE" env SCENIC_SCENARIO="$PWD/tools/scenarios/spike.qml" timeout 60 ./run.sh -platform offscreen
suite stores  check_done "p1auto\] DONE" env SCENIC_SCENARIO="$PWD/tools/scenarios/stores.qml" timeout 60 ./run.sh -platform offscreen

# --- GPU suites (need a display; skipped/soft where none) ---
suite webrtc  check_done "p3auto\].*DONE" ./tools/test-webrtc.sh
suite media   ./tools/test-media.sh
suite routing ./tools/test-routing.sh
# needs a real camera; SKIPs where there is none
suite camcycle ./tools/test-camera-cycle.sh
suite camleak  ./tools/test-camera-leak.sh
suite camregap ./tools/test-camera-regap.sh
suite camstop  ./tools/test-camera-stopped.sh
suite x11     ./tools/test-x11.sh
# every node type end to end, content checked by external tools
suite io      ./tools/test-io.py

cleanup
echo "----"
echo "PASS=$PASS FAIL=$FAIL SKIP=$SKIP$FAILED_SUITES"
[ -n "$SKIPPED_SUITES" ] && echo "skipped (never ran):$SKIPPED_SUITES"
[ "$FAIL" = 0 ]
