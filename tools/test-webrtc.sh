#!/bin/sh
# End-to-end telepresence test, headless:
# signalling server + external gst-launch producer + scenic-native in
# tools/scenarios/webrtc.qml (connect, discover, subscribe, publish, route).
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."

. "$HERE/lib-exit.sh"

. tools/env.sh
require_score

if test_display; then PLATFORM=""; else PLATFORM="-platform offscreen"; fi

cleanup() {
    [ -n "${PRODUCER_PID:-}" ] && kill "$PRODUCER_PID" 2>/dev/null || true
    [ -n "${SIGNALLER_PID:-}" ] && kill "$SIGNALLER_PID" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

"${GST_BIN}gst-webrtc-signalling-server" --host 127.0.0.1 --port 8443 \
    > /tmp/scenic-test-signaller.log 2>&1 &
SIGNALLER_PID=$!
sleep 1

"${GST_BIN}gst-launch-1.0" videotestsrc is-live=true pattern=ball \
    ! video/x-raw,width=320,height=240,framerate=30/1 ! videoconvert \
    ! x264enc tune=zerolatency bitrate=500 \
    ! webrtcsink signaller::uri=ws://127.0.0.1:8443 \
      meta="meta,name=extcam,peer_name=testpeer,media_type=video" \
    > /tmp/scenic-test-producer.log 2>&1 &
PRODUCER_PID=$!
sleep 2

rm -f ~/.config/ossia/failsafe.bit
# The app's status is at the far end of a pipe; carry it out through a file so
# a crash at exit is not mistaken for success.
RC=$(mktemp)
SINCE=$(now_epoch)
{ SCENIC_SCENARIO="$PWD/tools/scenarios/webrtc.qml" SCENIC_WS_DEBUG=1 timeout 60 ./run.sh $PLATFORM 2>&1; echo $? > "$RC"; } \
    | grep -E "p3auto|ws<|GStreamer parse error" || true
CODE=$(cat "$RC" 2>/dev/null || echo 0)
rm -f "$RC"
classify_exit "${CODE:-0}" "$SINCE" "p3auto" || exit 1
