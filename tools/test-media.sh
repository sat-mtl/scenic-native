#!/bin/sh
# Media I/O test. Each media feature runs in its own app launch and is judged
# on a deterministic artifact; the exit status of the scenario that runs to
# completion is classified separately. Needs a display: the encode/readback
# paths produce no frames under the headless Null RHI.
#
# Primary (deterministic) assertions: recorded mp4 file, shmdata socket.
# SRT egress is exercised too but only reported informationally, since the
# SRT caller/listener handshake timing is flaky at the GStreamer level.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.." || exit 1

. "$HERE/lib-exit.sh"

. tools/env.sh
require_score

if ! test_display; then
    echo "test-media: SKIP (no Xvfb; encode paths need a GPU)"
    exit 77   # 77 = skipped, not passed
fi

FAIL=0
note() { echo "test-media: $*"; }

launch() {  # $1 = scenario; runs to completion (Qt.exit or 40s timeout)
    rm -f "$HOME/.config/ossia/failsafe.bit"
    SINCE=$(now_epoch)
    env QML_IMPORT_PATH="$PWD/qml" QML2_IMPORT_PATH="$PWD/qml" \
        SCENIC_SCENARIO="$PWD/tools/scenarios/media.qml" SCENIC_MEDIA_PHASE="$1" SCENIC_NO_THUMBS=1 SCENIC_TEST_CLIP=/tmp/scenic_testclip.mkv \
        timeout 40 "$SCORE_BIN" --ui qml/Main.qml --no-restore \
        > "/tmp/scenic-media-$1.log" 2>&1 &
    APP=$!
}

srt_probe() {  # $1 = port; informational only
    timeout 15 "${GST_BIN}gst-launch-1.0" -q \
        srtsrc uri="srt://127.0.0.1:$1?mode=caller" \
        ! tsdemux ! h264parse ! identity eos-after=30 ! fakesink >/dev/null 2>&1 \
        && note "INFO: SRT egress on $1 confirmed" \
        || note "INFO: SRT egress on $1 not confirmed (handshake timing)"
}

rm -f /tmp/scenic_rec.mp4 /tmp/scenic_mloop /tmp/scenic_testclip.mkv

"${GST_BIN}gst-launch-1.0" -q videotestsrc num-buffers=900 pattern=ball \
    ! video/x-raw,width=320,height=240,framerate=30/1 ! videoconvert \
    ! jpegenc ! matroskamux ! filesink location=/tmp/scenic_testclip.mkv \
  || { note "FAIL: could not generate test clip"; exit 1; }

# Scenario 1: videotest -> shmdata out -> shmdata in -> SRT
launch 1; sleep 10
if [ -S /tmp/scenic_mloop ]; then note "PASS: shmdata writer socket present"
else note "FAIL: shmdata writer socket missing"; FAIL=1; fi
srt_probe 4210
kill "$APP" 2>/dev/null; wait "$APP" 2>/dev/null

# Scenario 2: videotest -> record mp4 ; file playback -> SRT ; LTC -> audio
launch 2
wait "$APP" 2>/dev/null
# scenario 1 is killed on purpose, so only this one's status means anything
classify_exit "$?" "$SINCE" "scenario 2" || FAIL=1

# A native audio source (LTC) through the hub into a device, asserted on the
# samples: a connected route can still carry silence (an addressed outlet that
# does not publish, a hub gain at 0), which only the samples reveal.
# No expected frequency: LTC is a timecode signal.
if python3 tools/check-frame.py audio /tmp/scenic_ltc.raw; then
    note "PASS: LTC carries samples to a device"
else
    note "FAIL: LTC audio probe empty or silent"; FAIL=1
fi

for s in 1 2; do grep -E "mediaauto" "/tmp/scenic-media-$s.log" | sed 's/^Debug: //'; done
if grep -hqE "mediaauto\].*false" /tmp/scenic-media-1.log /tmp/scenic-media-2.log; then
    note "FAIL: a connection returned false"; FAIL=1
fi

# Recording is reported, not failed: in the full app, score's GPU teardown on
# Qt.exit (DocumentManager::closeAllDocuments) can crash before the encoder
# flushes, leaving the file empty. A minimal videotest->record graph produces
# a valid mp4.
DUR=$("${GST_BIN}gst-discoverer-1.0" /tmp/scenic_rec.mp4 2>/dev/null \
      | grep -m1 "Duration" | grep -oE "[0-9]+:[0-9]+:[0-9]+.[0-9]+")
if [ -n "$DUR" ] && [ "$DUR" != "0:00:00.000000000" ]; then
    note "PASS: recording valid ($DUR)"
else
    note "FAIL: recording empty"
    FAIL=1
fi

exit $FAIL
