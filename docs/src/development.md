# Development

Scenic is QML only: a shell (`qml/Main.qml`) and a module (`qml/Scenic/`)
driving the ossia score engine through score's QML API. There is no C++ to
build; you need an ossia score binary with the `score-addon-ndi` and
`score-addon-ltc` addons.

## Running from a checkout

```sh
SCORE_BIN=/path/to/ossia-score ./run.sh
```

| Variable | Meaning |
|---|---|
| `SCORE_BIN` | the ossia score binary; default: `ossia-score` on the `PATH` |
| `SCENIC_GST_SDK` | a GStreamer build to use instead of the system's, given as its prefix (`bin/`, `lib/`, `libexec/`): for instance one with gst-plugins-rs |

`./run.sh --debug` opens score's own editor beside the interface, which shows
the graph the stores build.

## Layout

| Path | Contents |
|---|---|
| `qml/Main.qml` | the window: menus, matrix, panels |
| `qml/Scenic/Stores/` | state: nodes, connections, scenes, sessions, settings, telepresence, data bridges, undo |
| `qml/Scenic/Views/`, `Components/` | the interface |
| `qml/Scenic/Nodes/` | one file per source or destination type |
| `qml/Scenic/shaders/` | the ISF shaders of the colour, crop and geometry stages |
| `demo/browser/` | the web viewer of [Streaming to a browser](browser.md) |
| `tools/` | test suites, scenarios and fixtures |
| `docs/` | this documentation |

The stores build everything at runtime in an empty score document: for each
node a device and a chain of processes ending in a *hub*, and score cables
between hubs for the connections. Every change goes through score's command
stack, which gives undo and redo.

## Adding a node type

Add a file to `qml/Scenic/Nodes/`; the catalog loads every file there. A type
is a `NodeType`:

```qml
import Scenic

NodeType {
    kind: "mydevice"                       // stable id, saved in sessions
    label: Translations.t("My Device")
    role: "source"; mediaType: "video"; category: "Video In"
    protocol: Uuids.gstreamer              // the score device behind it
    fields: [
        { key: "port", label: Translations.t("Port"), type: "int", def: 5000 }
    ]
    makeSettings: p => Pipelines.gstVideo("udpsrc port=" + p.port + " ! … ! appsink name=video")
    addr: name => name + ":/video"
}
```

`Components/NodeType.qml` documents every property.

### Per-platform options

- `platforms: ["linux", "osx"]` on a type limits it to those systems
  (`Qt.platform.os` values); elsewhere it is absent from the menus.
- The same `platforms` key on a field, or on an enum option, limits that
  field or option.
- `byPlatform({ windows: …, osx: …, default: … })` picks a value per system,
  for defaults or option lists:

  ```qml
  { key: "device", label: Translations.t("Device"),
    def: byPlatform({ windows: "COM3", osx: "/dev/cu.usbserial", default: "/dev/ttyUSB0" }) }
  ```

Code that reads a type's fields goes through `NodeCatalog.fieldsOf(recipe)`,
which applies the field and option filters.

## Translations

Interface strings go through `Translations.t("English text")`; the French
strings are in `qml/Scenic/Translations.qml`.

## Tests

`tools/run-tests.sh` runs every suite. Suites that render use a private Xvfb
display, never the desktop; the others run headless.

| Suite | Checks |
|---|---|
| `lint` | qmllint over the QML |
| `stress` | the node catalog, a seeded random sequence of store operations with invariants checked after each one, and session round trips |
| `proto` | every node type against what score's devices accept, routing rules, and creation of every type in the engine |
| `bridges` | data nodes over real sockets: codecs, MIDI/OSC conversion, sessions |
| `stores` | the stores end to end: scenes, undo, sessions, settings |
| `webrtc` | discovery, subscription and publication through a local signalling server |
| `media` | recording, shmdata and SRT outputs, checked on what they produce |
| `routing` | rendered video and audio through the matrix, checked pixel by pixel and sample by sample |
| `x11` | the random sequence again, with rendering |
| `io` | every source and destination type, with known content checked by external tools |

`tools/test-io.py` can run on its own: `-k PATTERN` selects cases, `--list`
lists them, `--roundtrip` also saves and reloads the session before checking
again. A case whose prerequisite is missing (a GStreamer element, a device,
PipeWire, the NDI runtime, X11) reports `SKIP` with the reason. The video
taps need `gst-launch-1.0`; some cases also use `ffmpeg`, `xdotool`,
`pw-link` and a `v4l2loopback` device labelled `scenic-test`. A shmdata
GStreamer plugin that is not installed can be named with
`SCENIC_SHMDATA_GST`, sh4lt's `shflow` with `SCENIC_SHFLOW`.

## Documentation

The documentation is written in English in `docs/src/`; its French
translation is `docs/po/fr.po`, through
[mdbook-i18n-helpers](https://github.com/google/mdbook-i18n-helpers). To build
both languages:

```sh
cd docs
MDBOOK_BOOK__LANGUAGE=en mdbook build -d book/en
MDBOOK_BOOK__LANGUAGE=fr mdbook build -d book/fr
```

After changing the English text, update the translation template and merge it
into the French file:

```sh
cd docs
MDBOOK_OUTPUT='{"xgettext": {}}' mdbook build -d po
msgmerge --update po/fr.po po/messages.pot
```

then translate the new and fuzzy entries of `po/fr.po`.
