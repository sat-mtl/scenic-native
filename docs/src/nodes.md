# Node types

Types marked *GStreamer* need GStreamer installed (see
[Installation](installation.md)); *WebRTC* also needs gst-plugins-rs. NDI®
types need the NDI runtime. Types limited to some systems only appear in the
menus there.

## Sources

| Type | Media | Systems | Needs |
|---|---|---|---|
| Camera | video | all | |
| Photo Camera | video | all | libgphoto2 |
| Screen / Window Capture | video | all | |
| Video File | video | all | |
| Video Test Pattern | video | all | GStreamer |
| NDI® Input | video | all | NDI runtime |
| Shmdata Input | video | Linux, macOS | |
| Sh4lt Input | video | Linux | |
| PipeWire Input | video | Linux | |
| Spout Input | video | Windows | |
| Syphon Input | video | macOS | |
| FFmpeg Input | video | all | |
| GStreamer Pipeline (video in) | video | all | GStreamer |
| Audio Input | audio | all | |
| Audio Test Signal | audio | all | GStreamer |
| Audio File | audio | all | GStreamer |
| LTC Generator | audio | all | |
| GStreamer Pipeline (audio in) | audio | all | GStreamer |
| MIDI Input | data | all | |
| Serial Input | data | all | |
| UDP Input, TCP Input | data | all | |
| WebSocket Input | data | all | |
| WebRTC Video, WebRTC Audio | video, audio | all | WebRTC; added from the Peers panel |

## Destinations

| Type | Media | Systems | Needs |
|---|---|---|---|
| Video Monitor | video | all | |
| Record to File | video | all | |
| RTMP Streaming | video | all | |
| SRT Streaming | video | all | |
| FFmpeg Output | video | all | |
| NDI® Output | video | all | NDI runtime |
| Shmdata Output | video | Linux, macOS | |
| Sh4lt Output | video | Linux | |
| PipeWire Output | video | Linux | |
| Spout Output | video | Windows | |
| Syphon Output | video | macOS | |
| GStreamer Pipeline (video out) | video | all | GStreamer |
| WebRTC Publish (video) | video | all | WebRTC |
| Audio Output | audio | all | |
| GStreamer Pipeline (audio out) | audio | all | GStreamer |
| WebRTC Publish (audio) | audio | all | WebRTC |
| MIDI Output | data | all | |
| Serial Output | data | all | |
| UDP Output, TCP Output | data | all | |
| WebSocket Output | data | all | |

## Data

Data nodes carry messages, as raw bytes, OSC or MIDI depending on their
**Payload** setting. Between a source and a destination of different payloads,
messages are converted with the usual mapping, `/midi/<channel>/<event>[/<number>] <value>`:
MIDI note 60 at velocity 100 on channel 1 is the OSC message `/midi/1/note/60 100`,
control change 7 is `/midi/1/cc/7`, and so on for `aftertouch`, `program`,
`pressure` and `bend`. `/midi/raw` carries raw MIDI bytes.
