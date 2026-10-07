# Shared exit-status classification for the suites that judge by log marker.
# Sourced, not executed, by a script that sets HERE to its own directory:
#   HERE="$(cd "$(dirname "$0")" && pwd)"; . "$HERE/lib-exit.sh"
#
# The "DONE" marker decides whether the scenario's assertions passed. The exit
# status is classified on its own, so that a new crash at exit, or a run killed
# by `timeout` mid-sweep, is not mistaken for a pass:
#
#   0          clean
#   124        killed by timeout -> always a failure
#   1..128     plain nonzero exit -> a failure
#   128+N      killed by signal N -> a failure unless its stack trace matches an
#              entry in tools/known-crashes.txt
#
# Set SCENIC_ALLOW_EXIT_CRASH=1 to downgrade an unclassified crash to a warning
# (for a machine where a new teardown crash is a known nuisance and you still
# want the suites usable while it is being fixed).

# Node types that only the tests use (probes, fixed sources): NodeCatalog
# loads them from here in addition to the app's own.
export SCENIC_NODE_PATH="${SCENIC_NODE_PATH:-$HERE/fixtures}"

# test_display: give a suite that renders a display of its own. A private
# Xvfb is started, so nothing appears on the desktop and no window manager
# moves the windows being captured; it exits with the script that started it.
# SCENIC_TEST_DISPLAY names a display to use instead - run-tests.sh sets it
# to the one Xvfb it starts for all the suites. Returns 1 without Xvfb.
test_display() {
    if [ -n "${SCENIC_TEST_DISPLAY:-}" ]; then
        export DISPLAY="$SCENIC_TEST_DISPLAY"
        return 0
    fi
    command -v Xvfb >/dev/null 2>&1 || return 1
    num=$(mktemp)
    Xvfb -displayfd 3 -screen 0 1920x1080x24 -nolisten tcp 3>"$num" >/dev/null 2>&1 &
    xvfb=$!
    i=0
    while [ ! -s "$num" ] && [ $i -lt 50 ]; do sleep 0.1; i=$((i + 1)); done
    [ -s "$num" ] || { kill "$xvfb" 2>/dev/null; rm -f "$num"; return 1; }
    DISPLAY=":$(cat "$num")"
    export DISPLAY
    export SCENIC_TEST_DISPLAY="$DISPLAY"
    rm -f "$num"
    # stop it when this script ends, whatever traps the script sets itself
    parent=$$
    ( while kill -0 "$parent" 2>/dev/null; do sleep 1; done; kill "$xvfb" 2>/dev/null ) &
    return 0
}

# now_epoch: timestamp to hand to classify_exit, taken *before* the run so the
# core lookup cannot pick up an older crash.
now_epoch() { date +%s; }

# crash_trace SINCE -> the top frames of the newest ossia-score crash since
# epoch SINCE, or nothing.
#
# Two sources, in order. The journal's own backtrace (systemd-coredump records
# one even when the core file itself is not stored) is useless for score: its
# crash handler is on top of the crashing thread and the unwinder gives up
# there, leaving only `syscall` + libLLVM. So when the core file is stored,
# unwind it with gdb, which resolves score's own symbols and shows the real
# site; fall back to the journal frames otherwise.
# strip_handler_frames: stdin -> stdout, dropping everything up to and including
# the signal-handler frame, so what is left starts at the real crash site.
strip_handler_frames() {
    awk '{ a[NR] = $0; if ($0 ~ /__restore_rt|signal handler called/) start = NR }
         END { for (i = start + 1; i <= NR; i++) print a[i] }'
}

crash_trace() {
    command -v coredumpctl >/dev/null 2>&1 || return 0
    # rows are "Mon 2026-09-07 12:59:10 EDT <pid> <uid> ...", oldest first: keep
    # the first all-digits field of the last row
    pid=$(coredumpctl -q --no-pager list --since "@$1" ossia-score 2>/dev/null \
          | awk 'NR>1 { for (i = 1; i <= NF; i++) if ($i ~ /^[0-9]+$/) { p = $i; break } }
                 END { print p }')
    [ -n "${pid:-}" ] || return 0

    if command -v gdb >/dev/null 2>&1; then
        exe=$(coredumpctl -q --no-pager info "$pid" 2>/dev/null \
              | awk '/^ *Executable:/ { print $2; exit }')
        core="${TMPDIR:-/tmp}/scenic-core.$pid"
        if [ -n "${exe:-}" ] && [ -x "$exe" ] \
           && coredumpctl -q dump "$pid" -o "$core" >/dev/null 2>&1; then
            # gdb echoes the faulting frame once before `bt`, hence the dedupe
            # by frame number
            frames=$(timeout 300 gdb -q -batch -ex "bt 16" "$exe" "$core" 2>/dev/null \
                     | grep -E '^#[0-9]+' | awk '!seen[$1]++' \
                     | strip_handler_frames | head -8)
            rm -f "$core"
            if [ -n "$frames" ]; then
                printf '%s\n' "$frames"
                return 0
            fi
        fi
    fi

    # Keep the crashing thread (the first block), and drop the frames of
    # score's own crash handler: everything up to and including __restore_rt is
    # the handler, not the crash site.
    coredumpctl -q --no-pager info "$pid" 2>/dev/null \
        | sed -n '/Stack trace of thread/,$p' \
        | awk '/Stack trace of thread/ { n++ } n == 1' \
        | grep -E '^ *#[0-9]+' \
        | strip_handler_frames | head -8
}

# match_known_crash TRACE -> the name of the matching allow-list entry, if any
match_known_crash() {
    [ -n "$1" ] || return 0
    f="${HERE:-$(dirname "$0")}/known-crashes.txt"
    [ -r "$f" ] || return 0
    while IFS= read -r line; do
        case "$line" in ''|\#*) continue ;; esac
        nm=${line%%|*}
        rx=${line#*|}
        if printf '%s\n' "$1" | grep -qE "$rx"; then
            printf '%s' "$nm"
            return 0
        fi
    done < "$f"
}

# gpu_oom LOG -> prints a diagnosis if the run died for want of GPU memory
#
# The GPU is shared with whatever else is on the machine. When the total
# approaches the card's capacity, a swapchain allocation fails and the driver
# crashes inside QRhiSwapChain::createOrResize - a segfault in the graphics
# stack that says nothing about this application. The app logs the failed
# allocation just before dying, so the signature is reliable.
gpu_oom() {
    [ -n "${1:-}" ] && [ -r "$1" ] || return 1
    grep -qE "No suitable memory type found|Failed to create new swapchain" "$1" || return 1
    if command -v nvidia-smi > /dev/null 2>&1; then
        mem=$(nvidia-smi --query-gpu=memory.used,memory.total --format=csv,noheader 2>/dev/null)
        others=$(nvidia-smi --query-compute-apps=pid,used_memory --format=csv,noheader 2>/dev/null \
                 | wc -l)
        echo "      the GPU ran out of memory (now $mem, $others process(es) using it)"
    else
        echo "      the GPU ran out of memory"
    fi
    echo "      -> an environment problem, not a regression: rerun when the card is free"
    return 0
}

# classify_exit CODE SINCE LABEL [LOG]
#   Prints nothing for a clean exit. Otherwise prints what happened and returns
#   1 if the exit status must fail the suite (0 = tolerated).
classify_exit() {
    code=$1; since=$2; label=$3; runlog=${4:-}
    [ "$code" = 0 ] && return 0
    # 77 is a suite deciding it cannot run here (no display); the caller reports
    # it as SKIP, it is not an exit-status problem.
    [ "$code" = 77 ] && return 0
    if [ "$code" = 124 ]; then
        echo "  $label: TIMED OUT (killed before it could finish)"
        return 1
    fi
    if [ "$code" -lt 128 ]; then
        echo "  $label: exited with status $code"
        return 1
    fi
    sig=$((code - 128))
    nm=$(kill -l "$sig" 2>/dev/null || echo "$sig")
    trace=$(crash_trace "$since")
    known=$(match_known_crash "$trace")
    if [ -n "$known" ]; then
        echo "  $label: killed by SIG$nm at exit; known upstream bug: $known"
        return 0
    fi
    if gpu_oom_check=$(gpu_oom "$runlog"); then
        echo "  $label: killed by SIG$nm in the graphics driver, out of GPU memory"
        printf '%s\n' "$gpu_oom_check"
        return 1
    fi
    echo "  $label: killed by SIG$nm - UNCLASSIFIED crash"
    if [ -n "$trace" ]; then
        printf '%s\n' "$trace" | head -5 | sed 's/^ */      /'
    else
        echo "      (no stack trace: coredumpctl found no core for this run)"
    fi
    if [ "${SCENIC_ALLOW_EXIT_CRASH:-0}" = 1 ]; then
        echo "      tolerated: SCENIC_ALLOW_EXIT_CRASH=1"
        return 0
    fi
    return 1
}
