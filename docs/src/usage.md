# Using Scenic

## The matrix

**+ Sources** and **+ Destinations** open menus of node types, grouped by
category. Some types are created at once; others first ask for a few settings,
such as a file, a URL or a stream name. Enumerated devices (cameras, NDI®
sources, audio devices) are listed by name.

Sources are rows and destinations are columns. Click a cell to connect a source
to a destination, and click it again to disconnect them. A source can feed any
number of destinations:

- **Video:** up to eight sources connected to one video destination are
  composited.
- **Audio:** the sources connected to one audio destination are mixed.
- **Data:** messages are forwarded, converted between OSC, MIDI and raw bytes
  as each end requires.

Each node has a header with its name and, for video, a live thumbnail.

- **Preview** (⤢): a large view of the source.
- **Remove** (✕): delete the node and its connections.
- Click the header to open the **inspector**.

## The inspector

The inspector shows the selected node:

- **Settings:** what the node was created with (file, address, stream name…).
  Changing them rebuilds the node; its connections are kept.
- **Device:** properties of the underlying device that can change live, such
  as an encoder's bitrate.
- **Controls:** the node's processing: colour adjustments, crop and geometry
  for video, gain for audio. Each slider gesture is one undo step.

## Scenes

The tabs above the matrix are scenes, each a set of connections.

- Click a tab to switch to its connections.
- Double-click a tab to rename it.
- **+** adds a scene, starting with no connections; **✕** removes one.

Switching scenes changes only the connections; the nodes stay.

## Sessions

The **Session** menu saves and loads sessions. A session holds the nodes,
their settings and controls, the connections and the scenes. **Ctrl+S**
(**⌘S** on macOS) saves the current session.

Sessions are stored in `Documents/Scenic/sessions` in your home folder.

## Undo

Every change (creating, removing or reconfiguring a node, connecting,
switching scenes, moving a control) can be undone and redone with the
system's shortcuts (**Ctrl+Z** and **Ctrl+Shift+Z** or **Ctrl+Y**; **⌘Z** and
**⇧⌘Z** on macOS), or with the arrows of the toolbar.

## Settings

The **Settings** page holds the interface language, the thumbnails, and the
[telepresence](telepresence.md) settings. They are kept in the user's
configuration folder:

| System | Folder |
|---|---|
| Linux | `~/.config/scenic-native` |
| macOS | `~/Library/Application Support/scenic-native` |
| Windows | `%APPDATA%\scenic-native` |

The status bar shows the number of nodes and connections and, on Linux, the
CPU, memory and network load.
