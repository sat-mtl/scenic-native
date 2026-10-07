#!/bin/sh
# Browser streaming demo: scenic-native publishes a test pattern and a test
# tone over WebRTC, and a web page plays them. See docs/src/browser.md.
#
#   tools/demo-browser.sh           run it locally, then open the URL
#   tools/demo-browser.sh --lan     also let other machines on the network watch
#   tools/demo-browser.sh --turn    relay all media through a local TURN server
#   tools/demo-browser.sh --check   automated run: private Xvfb, headless Chrome;
#                                   exits 0 once the page plays video and audio
# The options combine, e.g. --check --turn.
#
# Environment: SCORE_BIN and SCENIC_GST_SDK (see tools/env.sh), SIGNALLER_PORT (8443),
# HTTP_PORT (8080), TURN_PORT (3478), TURNSERVER (coturn's turnserver binary);
# --check only: CHROME (google-chrome), CHECK_SECONDS.
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."
. "$HERE/lib-exit.sh"
. tools/env.sh
require_score

LAN=0 TURN=0 CHECK=0
for arg in "$@"; do
    case "$arg" in
        --lan) LAN=1 ;;
        --turn) TURN=1 ;;
        --check) CHECK=1 ;;
        *) sed -n '2,15p' "$0"; exit 2 ;;
    esac
done

# --check uses ports of its own, so it can run next to a demo in progress
if [ $CHECK = 1 ]; then
    SIGNALLER_PORT="${SIGNALLER_PORT:-8463}"
    HTTP_PORT="${HTTP_PORT:-8093}"
    TURN_PORT="${TURN_PORT:-3498}"
else
    SIGNALLER_PORT="${SIGNALLER_PORT:-8443}"
    HTTP_PORT="${HTTP_PORT:-8080}"
    TURN_PORT="${TURN_PORT:-3478}"
fi
BIND=127.0.0.1
[ $LAN = 1 ] && BIND=0.0.0.0
# demo credentials; the password has a '/' and a ':' on purpose, which only
# work if they are escaped in the TURN URI
TURN_USER=scenic
TURN_PASSWORD="demo/pass:1"

SIGNALLING_SERVER="${GST_BIN}gst-webrtc-signalling-server"
command -v "$SIGNALLING_SERVER" > /dev/null || {
    echo "demo-browser.sh: gst-webrtc-signalling-server not found; install" \
         "gst-plugins-rs, or set SCENIC_GST_SDK to a GStreamer build that has it" >&2
    exit 1
}
if [ $TURN = 1 ]; then
    TURNSERVER="${TURNSERVER:-$(command -v turnserver || true)}"
    [ -n "$TURNSERVER" ] && [ -x "$TURNSERVER" ] || {
        echo "demo-browser.sh: --turn needs coturn: install it (apt install coturn)" \
             "or set TURNSERVER to its turnserver binary" >&2
        exit 1
    }
fi

LOGS="${TMPDIR:-/tmp}/scenic-browser-demo"
mkdir -p "$LOGS"
PIDS=""
cleanup() {
    for pid in $PIDS; do kill "$pid" 2>/dev/null || true; done
}
trap cleanup EXIT
trap 'exit 130' INT TERM

port_busy() { ss -lntu "sport = :$1" 2>/dev/null | grep -q -e LISTEN -e UNCONN; }
PORTS="$SIGNALLER_PORT $HTTP_PORT"
[ $TURN = 1 ] && PORTS="$PORTS $TURN_PORT"
for port in $PORTS; do
    if port_busy "$port"; then
        echo "demo-browser.sh: port $port is in use (a demo already running?);" \
             "set SIGNALLER_PORT / HTTP_PORT / TURN_PORT" >&2
        exit 1
    fi
done

"$SIGNALLING_SERVER" --host "$BIND" --port "$SIGNALLER_PORT" > "$LOGS/signaller.log" 2>&1 &
PIDS="$PIDS $!"
python3 -m http.server "$HTTP_PORT" --bind "$BIND" --directory demo/browser \
    > "$LOGS/http.log" 2>&1 &
PIDS="$PIDS $!"
if [ $TURN = 1 ]; then
    # Long-term credentials, plain UDP/TCP. Loopback peers are allowed
    # because both ends of the demo can be on the same host.
    TURN_ADDRS="--listening-ip=$BIND"
    [ $LAN = 1 ] && TURN_ADDRS=""
    "$TURNSERVER" -n --no-cli --no-tls --no-dtls --log-file=stdout --verbose \
        --userdb="$LOGS/turndb" \
        $TURN_ADDRS --listening-port="$TURN_PORT" --min-port=49160 --max-port=49200 \
        --lt-cred-mech --realm=scenic.local --user="$TURN_USER:$TURN_PASSWORD" \
        --fingerprint --allow-loopback-peers > "$LOGS/turn.log" 2>&1 &
    PIDS="$PIDS $!"
fi

i=0
until port_busy "$SIGNALLER_PORT" && port_busy "$HTTP_PORT" \
      && { [ $TURN = 0 ] || port_busy "$TURN_PORT"; }; do
    i=$((i + 1))
    if [ $i -ge 50 ]; then
        echo "demo-browser.sh: a server did not start:" >&2
        tail -n 3 "$LOGS"/signaller.log "$LOGS"/http.log "$LOGS"/turn.log 2>/dev/null >&2
        exit 1
    fi
    sleep 0.1
done

if [ $CHECK = 1 ]; then
    test_display || { echo "demo-browser.sh: --check needs Xvfb" >&2; exit 1; }
fi

if [ $TURN = 1 ]; then
    export SCENIC_TURN="turn://127.0.0.1:$TURN_PORT"
    export SCENIC_TURN_USER="$TURN_USER" SCENIC_TURN_PASSWORD="$TURN_PASSWORD"
fi
SCENIC_SCENARIO="$PWD/tools/scenarios/browser-demo.qml" \
SCENIC_SIGNALLER="ws://127.0.0.1:$SIGNALLER_PORT" \
    ./run.sh > "$LOGS/app.log" 2>&1 &
APP=$!
PIDS="$PIDS $APP"

# the publications exist once the scenario says so
i=0
until grep -q "\[demo\] READY" "$LOGS/app.log" 2>/dev/null; do
    if ! kill -0 "$APP" 2>/dev/null || grep -q "\[demo\] FAILED" "$LOGS/app.log"; then
        echo "demo-browser.sh: the app failed to start the demo; see $LOGS/app.log" >&2
        exit 1
    fi
    i=$((i + 1))
    [ $i -lt 60 ] || { echo "demo-browser.sh: timed out; see $LOGS/app.log" >&2; exit 1; }
    sleep 1
done

# page address for a host; with --turn the page is told to relay everything
page_url() {
    url="http://$1:$HTTP_PORT/"
    if [ $TURN = 1 ]; then
        pass=$(python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "$TURN_PASSWORD")
        url="$url?turn=turn:$1:$TURN_PORT&user=$TURN_USER&pass=$pass&relay=1"
    fi
    echo "$url"
}

if [ $CHECK = 0 ]; then
    echo "Scenic is publishing \"scenic-video\" and \"scenic-audio\"."
    [ $TURN = 1 ] && echo "All media is relayed through the TURN server on port $TURN_PORT."
    echo "Open in a browser:"
    echo "    $(page_url 127.0.0.1)"
    if [ $LAN = 1 ]; then
        for ip in $(hostname -I 2>/dev/null); do
            case "$ip" in *:*) continue ;; esac
            echo "    $(page_url "$ip")   (from another machine)"
        done
    fi
    echo "Logs are in $LOGS. Ctrl-C (or closing Scenic) stops the demo."
    wait "$APP" || true
    exit 0
fi

# --check: a headless Chrome watches every stream until it reports both
CHROME="${CHROME:-google-chrome}"
PROFILE=$(mktemp -d)
URL="$(page_url 127.0.0.1)"
case "$URL" in *\?*) URL="$URL&" ;; *) URL="$URL?" ;; esac
URL="${URL}autoplay=1&signaller=ws://127.0.0.1:$SIGNALLER_PORT"
( unset DISPLAY
  exec "$CHROME" --headless=new --no-first-run --no-default-browser-check \
      --user-data-dir="$PROFILE" --autoplay-policy=no-user-gesture-required \
      --enable-logging=stderr --log-level=0 "$URL" \
) > "$LOGS/chrome.log" 2>&1 &
PIDS="$PIDS $!"
trap 'cleanup; sleep 1; rm -rf "$PROFILE" 2>/dev/null || true' EXIT

i=0
while [ $i -lt 60 ]; do
    if grep -q "RECEIVING video" "$LOGS/chrome.log" \
       && grep -q "RECEIVING audio" "$LOGS/chrome.log"; then
        grep -o '\[viewer\] RECEIVING[^"]*' "$LOGS/chrome.log"
        # with --turn, a stream that did not go through the relay is a failure
        if [ $TURN = 1 ] && grep '\[viewer\] RECEIVING' "$LOGS/chrome.log" | grep -qv "path relay"; then
            echo "FAIL: a stream did not use the TURN relay" >&2
            exit 1
        fi
        # CHECK_SECONDS=N keeps watching N more seconds, then prints the
        # latest stats (frame rate, bitrate)
        if [ "${CHECK_SECONDS:-0}" -gt 0 ]; then
            sleep "$CHECK_SECONDS"
            for name in scenic-video scenic-audio; do
                grep -o "\[viewer\] stats ${name}[^\"]*" "$LOGS/chrome.log" | tail -n 1
            done
        fi
        echo "PASS: the browser plays Scenic's video and audio$( [ $TURN = 1 ] && echo ", relayed through TURN")"
        exit 0
    fi
    sleep 1
    i=$((i + 1))
done
grep -o '\[viewer\][^"]*' "$LOGS/chrome.log" | tail -n 20
echo "FAIL: no video and audio in the browser after 60 s; logs in $LOGS" >&2
exit 1
