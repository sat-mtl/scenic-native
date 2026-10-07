# Streaming to a browser

Any web browser can watch Scenic's WebRTC publications: the page in
`demo/browser/index.html` of the repository is a complete viewer, a single
file with no dependency. It works with any producer on a signalling server,
not only Scenic.

## The demo

From a checkout of the repository (see [Development](development.md)):

```sh
tools/demo-browser.sh
```

This starts a signalling server, serves the viewer page, and starts Scenic with
a test pattern and a test tone published as `scenic-video` and
`scenic-audio`. Open the address it prints, `http://127.0.0.1:8080/`, click
**Connect**, then **Watch** on each stream. Video starts muted, as browsers
require; the audio player has its own controls.

The matrix stays live: connect a camera to *Publish scenic-video* and the
browser shows it.

| Option | Effect |
|---|---|
| `--lan` | listen on every interface, so other machines can watch; prints one address per interface |
| `--turn` | also start a TURN server (coturn) with a demo account, and relay all media through it |
| `--check` | automated run, with Scenic on a virtual display and a headless Chrome; exits 0 once the page plays both streams |

The options combine. `--turn` needs coturn (`turnserver`). Environment
variables: `SIGNALLER_PORT` (8443), `HTTP_PORT` (8080), `TURN_PORT` (3478),
`TURNSERVER`, `CHROME`.

The browser must decode H.264 in WebRTC: Chrome, Chromium, Edge, Safari, or
Firefox with its OpenH264 plugin.

## The viewer page

The page connects to port 8443 of the host that served it, unless told
otherwise. Under each stream it shows the codec, resolution, frame rate,
bitrate and network path: `host` for a direct local address, `srflx` for an
address seen through NAT, `relay` for the TURN server.

| URL parameter | Effect |
|---|---|
| `signaller=ws://host:port` | signalling server, and connect at once |
| `autoplay=1` | watch every stream as it appears |
| `stun=stun:host:port` | STUN server |
| `turn=turn:host:port`, `user=`, `pass=` | TURN server and account (URL-encode the password) |
| `relay=1` | relay everything through the TURN server |

## From another machine

The other machine must reach this one on the page's port (8080), the
signalling port (8443) and, for media, UDP ports chosen during the
connection. With `--turn`, add the TURN port (3478, UDP and TCP) and the relay
ports (49160–49200, UDP).

| Symptom | Cause |
|---|---|
| *Cannot reach ws://…* | wrong address in the page's field, or a firewall |
| No streams listed | Scenic and the page use different signalling servers |
| *Connection failed* | no network path between the peers; try `--turn` |
| Black video | the browser cannot decode H.264 |
| No sound | press play: browsers block audible autoplay |
