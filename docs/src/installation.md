# Installation

## Packages

Builds for Linux (AppImage), macOS and Windows are on the
[releases page](https://github.com/sat-mtl/scenic-native/releases). The
`continuous` release follows the latest development version.

## GStreamer

Scenic uses the GStreamer installed on the computer, version 1.26 or later.
Without it, the test pattern, test tone, audio files, GStreamer pipelines and
WebRTC are unavailable; everything else works.

WebRTC also needs the `rswebrtc` plugin of gst-plugins-rs (`webrtcsink`,
`webrtcsrc`), and H.264 and Opus support. To check an installation:

```sh
gst-inspect-1.0 webrtcsink
```

- **macOS:** install the *runtime* package from
  [gstreamer.freedesktop.org](https://gstreamer.freedesktop.org/download/).
  It installs `GStreamer.framework` in `/Library/Frameworks`, where Scenic
  finds it, and includes WebRTC and H.264.
- **Windows:** install the *MSVC 64-bit runtime* from the same page, with the
  complete set of plugins, then add its `bin` folder (for instance
  `C:\Program Files\gstreamer\1.0\msvc_x86_64\bin`) to the `PATH`
  environment variable, so that Scenic finds it.
- **Linux:** install GStreamer and its plugins from your distribution
  (packages such as `gstreamer1.0-plugins-base`, `-good`, `-bad`, `-ugly`
  and `gstreamer1.0-libav`). WebRTC needs gst-plugins-rs, which not every
  distribution packages; it can be built from source, or used from a
  GStreamer build that includes it.

## NDI®

The NDI® source and destination need the NDI runtime, from
[ndi.video](https://ndi.video/tools/).

## From source

See [Development](development.md).
