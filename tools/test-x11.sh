#!/bin/sh
# Real-display (X11) gfx regression test.
#
# test-stress.sh runs -platform offscreen with a Null RHI: it validates store
# logic but never renders, so it cannot catch GPU-path crashes. This suite runs
# stress-test.qml against an X11 display, so the real QRhi backend renders
# through GfxContext's manual timer, the path where a failed
# QRhiGraphicsPipeline::create() (transient during graph rebuild) must not crash
# InvertYRenderer::finishFrame / quadRenderPass. Both the session round-trip
# and the during-playback fuzz churn devices, exercising stop/restart teardown
# and rebuild on the real GPU.
#
# The assertions are judged by the [stress] DONE marker, which prints only after
# all invariants + undo/redo pass; the exit status is judged separately by
# classify_exit (tools/lib-exit.sh), so a crash on the GPU path at exit is
# reported.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.." || exit 1

. "$HERE/lib-exit.sh"

. tools/env.sh
require_score
SEEDS="${SCENIC_X11_SEEDS:-1 2 3 7 13 42 99}"
OPS="${SCENIC_FUZZ_OPS:-80}"

# The whole point is to render on a real GPU, so a display is required.
if ! test_display; then
    echo "test-x11: SKIP (no Xvfb; needs a real GPU/X11 to render)"
    exit 77   # 77 = skipped, not passed
fi

FAIL=0

# set by run(); the caller classifies them with classify_exit
LAST_CODE=0
LAST_SINCE=0

run() {  # $1 = scenario, rest = extra env; renders on the real display (no -platform offscreen)
    scen=$1; shift
    rm -f "$HOME/.config/ossia/failsafe.bit"
    LAST_SINCE=$(now_epoch)
    env QML_IMPORT_PATH="$PWD/qml" QML2_IMPORT_PATH="$PWD/qml" SCENIC_STRESS="$scen" "$@" \
        timeout 90 "$SCORE_BIN" --ui tools/stress-test.qml --no-restore \
        > "/tmp/scenic-x11-$scen.log" 2>&1
    LAST_CODE=$?
    log="/tmp/scenic-x11-$scen.log"
    grep -q "\[stress\] DONE" "$log" && ! grep -q "\[stress\] FAIL" "$log"
}

# A seed can fail with no [stress] line at all; say what happened instead of
# printing nothing.
report_x11_failure() {
    log=$1
    if ! grep -q "\[stress\]" "$log"; then
        if [ ! -s "$log" ]; then
            echo "    (empty log: the app produced no output at all)"
        else
            echo "    (no [stress] marker: the app did not get as far as the scenario)"
            tail -3 "$log" | sed 's/^/      /'
        fi
        return
    fi
    grep -E "\[stress\]|SCORE_ASSERT|Pipeline not created" "$log" | tail -4 | sed 's/^/    /'
}

# The GPU is shared with whatever else runs on the host, and these
# scenarios push it hard: say what was already in use, so a later
# out-of-memory crash reads as the environment rather than a regression.
if command -v nvidia-smi > /dev/null 2>&1; then
    echo "GPU before starting: $(nvidia-smi --query-gpu=memory.used,memory.total \
        --format=csv,noheader 2>/dev/null)"
fi

echo "== session round-trip on real display (seeds: $SEEDS) =="
for s in $SEEDS; do
    if run session SCENIC_FUZZ_SEED="$s"; then
        :
    else
        echo "  seed $s: FAIL"
        report_x11_failure /tmp/scenic-x11-session.log
        FAIL=1
    fi
    classify_exit "$LAST_CODE" "$LAST_SINCE" "seed $s" "$log" || FAIL=1
done
[ "$FAIL" = 0 ] && echo "  all seeds round-tripped (real GPU render)"

echo "== during-playback fuzz on real display (seeds: $SEEDS, $OPS ops) =="
for s in $SEEDS; do
    if run fuzz SCENIC_FUZZ_PLAY=1 SCENIC_FUZZ_SEED="$s" SCENIC_FUZZ_OPS="$OPS"; then
        echo "  seed $s: OK ($(grep -oE 'survived .* ops' /tmp/scenic-x11-fuzz.log | tail -1))"
    else
        echo "  seed $s: FAIL"
        report_x11_failure /tmp/scenic-x11-fuzz.log
        FAIL=1
    fi
    classify_exit "$LAST_CODE" "$LAST_SINCE" "seed $s" "$log" || FAIL=1
done

echo "----"
[ "$FAIL" = 0 ] && echo "test-x11: ALL PASS" || echo "test-x11: FAILURES"
exit $FAIL
