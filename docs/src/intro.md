# Introduction

Scenic Native routes live audio, video and data between devices, software and
remote sites. It is a native reimplementation of
[Scenic](https://gitlab.com/sat-mtl/tools/scenic/scenic), the telepresence
application of the [Société des Arts Technologiques](https://sat.qc.ca), built
on the [ossia score](https://ossia.io) engine.

Everything happens in one **matrix**: sources are rows, destinations are
columns, and clicking a cell connects them.

- **Sources:** cameras, screen and window capture, video and audio files,
  test patterns and tones, audio inputs, NDI®, shmdata and Sh4lt, Spout and
  Syphon, GStreamer and FFmpeg inputs, MIDI, OSC and other data over UDP, TCP,
  WebSocket or serial, and streams from remote peers.
- **Destinations:** video windows, audio outputs, recording to a file, RTMP
  and SRT streaming, NDI®, shmdata and Sh4lt, Spout and Syphon, GStreamer and
  FFmpeg outputs, data outputs, and publication to remote peers.
- **Telepresence** uses WebRTC, through the same signalling protocol as
  Scenic 5, aiguille and web browsers.
- Several sources sent to one video destination are composited; audio
  sources sent to one output are mixed.
- **Scenes** store sets of connections and switch between them in one click.
- **Sessions** save everything: nodes, their settings, connections and scenes.
- Every edit can be undone.

The interface is available in English and French.
