# Telepresence

Scenic exchanges audio and video with remote peers over WebRTC. Peers find
each other through a **signalling server**, speaking the protocol of
gst-plugins-rs's `gst-webrtc-signalling-server`, as Scenic 5, aiguille and the
`gstwebrtc-api` web client do. Media then flows directly between peers, or
through a TURN server when they cannot reach each other.

WebRTC needs GStreamer 1.26 or later with gst-plugins-rs; see
[Installation](installation.md).

## Connecting

1. Run a signalling server, or get the address of one:

   ```sh
   gst-webrtc-signalling-server --host 0.0.0.0 --port 8443
   ```

2. In **Settings**, set the **Signalling server** (e.g. `ws://192.168.1.20:8443`)
   and a **Peer name**, which other peers see.
3. Open the **Peers** panel and click **Connect**.

## Publishing

Under **Publish**, **Video** and **Audio** each add a destination to the
matrix. Whatever is connected to it is sent to the peers that subscribe. The
**WebRTC Publish** destinations of the **+ Destinations** menu do the same,
with a stream name of your choice.

Video is sent as H.264 and audio as stereo Opus.

## Subscribing

The **Peers** panel lists the streams published on the server. **+** on a
stream adds it to the matrix as a source.

## STUN and TURN

When peers are on different networks, set these in **Settings**:

| Setting | Example | Notes |
|---|---|---|
| STUN server | `stun://stun.example.org:3478` | Empty: GStreamer's default, `stun://stun.l.google.com:19302` |
| TURN server | `turn://turn.example.org:3478` | `turns://` for TURN over TLS. Empty: no relay |
| TURN username, password | | |

They apply to WebRTC nodes created afterwards; to apply them to existing
nodes, recreate them or reload the session. The credentials are stored in the
settings file, never in sessions.

## Limits

- The signalling server is not authenticated: anyone who can reach it can
  list and watch the streams. Run it on a trusted network.
- Only static TURN credentials are supported.
