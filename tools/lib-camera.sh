# Did score actually open the camera? Shared by the camera suites.
#
# Neither of the obvious signals works:
#
#   - the scenario's own "opened N" marker only means NodeStore.create returned
#     an id, which it does whether or not the capture opened;
#   - score's "could not start the camera input" warning never leaves the
#     process in --ui mode. SafeQApplication installs its Qt message handler
#     only under SCORE_DEBUG, and the Messages panel that would otherwise
#     forward messages to stderr is not loaded without the GUI, so no qWarning
#     or qDebug from any plugin is visible. Measured: with the camera held by
#     another process for a whole run, all three opens were refused and the
#     warning appeared zero times.
#
# What is left is first-hand: a descriptor pointing at /dev/video* in score's
# own process. It needs nothing from Qt and, unlike fuser, cannot be confused
# with another process holding the camera.
#
# Linux-only (/proc). The suites that use it already require a local camera.

# camera_app_pid RUNNER -> the pid whose descriptors to watch.
# The suites launch score under `timeout`, so $! is timeout's pid and score is
# its child.
camera_app_pid() {
    _runner=$1
    _i=0
    while [ "$_i" -lt 100 ]; do
        _app=$(pgrep -P "$_runner" 2>/dev/null | head -1)
        if [ -n "$_app" ]; then
            printf '%s' "$_app"
            return 0
        fi
        sleep 0.1
        _i=$((_i + 1))
    done
    printf '%s' "$_runner"
}

# camera_fds PID -> how many /dev/video* descriptors that process holds.
camera_fds() {
    find /proc/"$1"/fd -type l -printf '%l\n' 2>/dev/null \
        | grep -c '^/dev/video' || echo 0
}

# sample_camera_fds RUNNER APP TRACE OUT
#   Appends "round=N fds=M" every 200 ms for as long as RUNNER lives, where N is
#   the number of "open " markers the scenario has written so far. Samples taken
#   before the first open land in round=0, which is where the mode enumeration's
#   own brief open goes; no round is judged on it.
sample_camera_fds() {
    _runner=$1; _app=$2; _trace=$3; _out=$4
    while kill -0 "$_runner" 2>/dev/null; do
        _held=$(camera_fds "$_app")
        _round=$(grep -c '^open ' "$_trace" 2>/dev/null) || _round=0
        echo "round=${_round} fds=${_held}" >> "$_out"
        sleep 0.2
    done
}

# camera_rounds_opened FDSFILE ROUNDS -> how many of rounds 1..ROUNDS ever had a
# camera descriptor open while they were the current round.
camera_rounds_opened() {
    _f=$1; _n=$2; _ok=0; _r=1
    while [ "$_r" -le "$_n" ]; do
        if awk -v r="$_r" '$1 == "round=" r && $2 != "fds=0" { f = 1 }
                           END { exit !f }' "$_f"; then
            _ok=$((_ok + 1))
        fi
        _r=$((_r + 1))
    done
    printf '%s' "$_ok"
}
