#!/bin/sh
# Data-validating routing integration tests. Runs each scenario in its own app
# launch (driving the real NodeStore/MatrixStore), routing solid-color/sine
# sources through the hub graph into GStreamer probe outputs, then asserts on
# the actual pixels/samples with tools/check-frame.py. Needs a display: the
# Gfx readback produces no frames under the headless Null RHI.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.." || exit 1

. "$HERE/lib-exit.sh"

. tools/env.sh
require_score

if ! test_display; then
    echo "test-routing: SKIP (no Xvfb; Gfx readback needs a GPU)"; exit 77   # 77 = skipped, not passed
fi

FAIL=0
run() {  # $1 = scenario
    rm -f "$HOME/.config/ossia/failsafe.bit"
    since=$(now_epoch)
    env QML_IMPORT_PATH="$PWD/qml" QML2_IMPORT_PATH="$PWD/qml" \
        SCENIC_IT="$1" timeout 40 "$SCORE_BIN" \
        --ui tools/integration-test.qml --no-restore \
        > "/tmp/scenic-it-$1.log" 2>&1
    # classify the app's status before the grep below replaces $?
    classify_exit "$?" "$since" "$1" || FAIL=1
    grep -E "^\[it\]|parse error" "/tmp/scenic-it-$1.log" | sed 's/^Debug: //' | grep -v Font
}
V() { python3 tools/check-frame.py video "$@" || FAIL=1; }
A() { python3 tools/check-frame.py audio "$@" || FAIL=1; }

echo "== single source (red) =="
rm -f /tmp/it_single.jpg; run single
V /tmp/it_single.jpg 255 0 0

echo "== additive mix (red, red+green, red+green+blue) =="
rm -f /tmp/it_mix_r.jpg /tmp/it_mix_rg.jpg /tmp/it_mix_rgb.jpg; run mix
V /tmp/it_mix_r.jpg   255 0   0
V /tmp/it_mix_rg.jpg  255 255 0
V /tmp/it_mix_rgb.jpg 255 255 255

echo "== remove a feed (yellow -> red after disconnect) =="
rm -f /tmp/it_remove.jpg; run remove
V /tmp/it_remove.jpg 255 0 0

echo "== remove source nodes (3 half-bright -> 1 half-red) =="
rm -f /tmp/it_many.jpg; run manyremove
V /tmp/it_many.jpg 128 0 0 40

echo "== video file playback + loop =="
if command -v ffmpeg >/dev/null 2>&1; then
    ffmpeg -y -f lavfi -i testsrc=size=320x240:rate=30:duration=5 \
        -c:v libx264 -pix_fmt yuv420p /tmp/scenic_clip.mp4 >/dev/null 2>&1
    rm -f /tmp/it_videofile.jpg; run videofile
    python3 - <<'PY' || FAIL=1
import numpy as np
from io import BytesIO
from PIL import Image
d = open('/tmp/it_videofile.jpg','rb').read(); s = d.rfind(b'\xff\xd8')
im = np.asarray(Image.open(BytesIO(d[s:])).convert('RGB'))
std = int(im.std())
# a 5s clip probed ~10s in must still have content -> decoded and looping
print("  it_videofile.jpg: std=%d %s" % (std, "OK" if std > 15 else "BLACK/no-play"))
raise SystemExit(0 if std > 15 else 1)
PY
else
    echo "  (ffmpeg absent — skipped clip generation)"
fi

echo "== engine undo/redo (counts must track) =="
run undo >/dev/null 2>&1
if grep -q "redo all: 1/1 conns=1" /tmp/scenic-it-undo.log \
   && grep -q "undo color: 0/0 conns=0" /tmp/scenic-it-undo.log; then
    echo "  undo/redo: OK"
else
    echo "  undo/redo: MISMATCH"; FAIL=1
    grep "\[it\]" /tmp/scenic-it-undo.log
fi

# Both probes stay connected to the end, so both files hold the final state.
# Saturation is luma-preserving (see shaders/README.md), so a pure red at
# saturation 0 is the grey of the same brightness: 0.2126 * 255 = 54.
echo "== live colour adjust (red -> desaturate to grey) =="
rm -f /tmp/it_ca_before.jpg /tmp/it_ca_after.jpg; run coloradjust
V /tmp/it_ca_after.jpg  54 54 54 25
V /tmp/it_ca_before.jpg 54 54 54 25

echo "== a reloaded session still carries video =="
rm -f /tmp/it_session.jpg; run sessionvideo
V /tmp/it_session.jpg 0 255 0

echo "== audio (sine 440) =="
rm -f /tmp/it_audio.raw; run audio
# Asserted on the samples, not on the graph: a connected audio route can still
# carry silence, e.g. an addressed outlet that does not publish to its address
# once it has a cable, a short channel read past its end by the GStreamer
# output, or the audio hub's Gain left at its default of 0.
A /tmp/it_audio.raw 440

echo "----"
[ "$FAIL" = 0 ] && echo "test-routing: ALL PASS" || echo "test-routing: FAILURES"
exit $FAIL
