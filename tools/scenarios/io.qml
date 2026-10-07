import QtQuick
import Scenic

// One input/output test, driven by tools/test-io.py through the JSON spec
// named by SCENIC_IO_SPEC (written by tools/test-io.py):
//
//   { nodes: [{ as, kind, label?, params?, pick?, webrtc?, deviceParams?,
//               after_ms? }],
//     connect: [[alias, alias]], hold_ms, release, roundtrip, load_over_open,
//     remove: [alias], signaller }
//
// Nodes are created in order, each `after_ms` after the previous one if set.
// `pick` selects an enumerated device whose name
// contains it; `webrtc` subscribes to the remote producer of that name; a
// params.device starting with "~" is resolved to the first MIDI port whose
// name contains the rest. Once everything is connected the scenario prints
// "[io] READY" and holds until the `release` file exists or hold_ms passes.
// With `roundtrip` it then saves the session, resets, loads it back two
// seconds later (or at once over the open session, with `load_over_open`),
// prints "[io] RELOADED" and holds again. Last, it removes the `remove` nodes (which
// finalises recordings) and exits with "[io] DONE".
Item {
    id: root

    property var shell
    readonly property var spec: JSON.parse(Score.readFile(
        Util.environmentVariable("SCENIC_IO_SPEC")))
    property var ids: ({})
    property int next: 0
    property int attempts: 0
    property int held: 0
    property string phase: "create"
    property bool failed: false

    function log(m) { console.log("[io]", m) }
    function fail(m) { failed = true; console.log("[io] FAIL:", m) }

    Component.onCompleted: {
        if (spec.signaller)
            SettingsStore.signallerUri = spec.signaller   // for this run only
        if (spec.nodes.some(n => n.webrtc))
            WebRtcStore.connect()
        timer.start()
    }

    //! The first MIDI port whose name contains `part`.
    function midiPort(part, outbound) {
        const list = outbound ? Protocols.outboundMIDIDevices()
                              : Protocols.inboundMIDIDevices()
        for (const p of list ?? [])
            if (String(p.Name).includes(part) || String(p.DisplayName).includes(part))
                return p.Name
        return null
    }

    function resolveParams(n: var, recipe: var): var {
        const p = Object.assign({}, n.params ?? {})
        if (typeof p.device === "string" && p.device.startsWith("~")) {
            const name = midiPort(p.device.substring(1), recipe.role === "destination")
            if (!name)
                return null
            p.device = name
        }
        return p
    }

    //! An enumerated device matching `pick`, or null while none is listed.
    function findDevice(kind, pick) {
        for (const d of shell.devicesFor(kind)) {
            if (d.items) {   // cameras come grouped per device
                if (d.title.includes(pick) && d.items.length > 0)
                    return d.items[0]
            } else if (String(d.name).includes(pick) || String(d.category).includes(pick)) {
                return d
            }
        }
        return null
    }

    //! Create one node: its id, "" on failure, null if not possible yet.
    function create(n) {
        const r = NodeCatalog.recipe(n.kind)
        if (!r) {
            fail("unknown kind " + n.kind)
            return ""
        }
        const label = n.label ?? n.as
        if (n.after_ms && attempts * timer.interval < n.after_ms)
            return null
        if (n.pick) {
            const dev = findDevice(n.kind, n.pick)
            return dev ? (NodeStore.create(r, dev.settings, label) ?? "") : null
        }
        if (n.webrtc) {
            if (!WebRtcStore.connected)
                return null
            for (let i = 0; i < WebRtcStore.producers.count; ++i) {
                const p = WebRtcStore.producers.get(i)
                if (p.name === n.webrtc)
                    return WebRtcStore.subscribe(p.producerId, p.name, p.peerName,
                                                 p.mediaType) ?? ""
            }
            return null
        }
        const params = resolveParams(n, r)
        if (!params)
            return null
        const settings = r.makeSettings ? r.makeSettings(params) : undefined
        return NodeStore.create(r, settings, label, undefined, params) ?? ""
    }

    function wire() {
        for (const n of spec.nodes)
            for (const addr in n.deviceParams ?? {})
                Device.write(ids[n.as] + "_dev:" + addr, n.deviceParams[addr])
        for (const [a, b] of spec.connect ?? [])
            if (!MatrixStore.connect(ids[a], ids[b]))
                fail("could not connect " + a + " -> " + b)
    }

    //! The driver releases the scenario once it has checked; hold_ms only
    //! bounds the wait. It must outlast the slowest check, or the scenario
    //! moves on while that check is still running.
    function released() {
        held += timer.interval
        return held >= (spec.hold_ms ?? 90000)
               || (spec.release && Util.fileExists(spec.release))
    }

    function finish() {
        timer.stop()
        for (const a of spec.remove ?? [])
            NodeStore.remove(ids[a])
        Qt.callLater(() => exitTimer.start())
    }

    Timer {
        id: timer
        interval: 250
        repeat: true
        onTriggered: {
            switch (root.phase) {
            case "create": {
                if (root.next >= root.spec.nodes.length) {
                    root.wire()
                    root.log("READY " + JSON.stringify(root.ids))
                    root.phase = "hold"
                    break
                }
                const n = root.spec.nodes[root.next]
                const id = root.create(n)
                if (id === null) {
                    if (++root.attempts > 120) {   // 30 s
                        root.fail("gave up waiting for " + n.as + " (" + n.kind + ")")
                        root.finish()
                    }
                    break
                }
                if (id === "") {
                    root.fail("could not create " + n.as + " (" + n.kind + ")")
                    root.finish()
                    break
                }
                const ids = root.ids
                ids[n.as] = id
                root.ids = ids
                root.next++
                root.attempts = 0
                break
            }
            case "hold":
                if (!root.released())
                    break
                if (root.spec.roundtrip) {
                    if (Util.fileExists(root.spec.release))
                        Util.removeFile(root.spec.release)
                    root.held = 0
                    if (!SessionStore.save("io_roundtrip"))
                        root.fail("could not save the session")
                    // loading over the open session is what the Load menu
                    // does; resetting first isolates restore from teardown
                    if (!root.spec.load_over_open)
                        SessionStore.reset()
                    root.phase = "load"
                    break
                }
                root.finish()
                break
            case "load":
                if (!root.spec.load_over_open && (root.held += timer.interval) < 2000)
                    break
                root.held = 0
                if (!SessionStore.load("io_roundtrip"))
                    root.fail("could not load the session")
                SessionStore.remove("io_roundtrip")
                root.log("RELOADED")
                root.phase = "reloaded"
                break
            case "reloaded":
                if (root.released())
                    root.finish()
                break
            }
        }
    }

    // time for removed nodes to flush and close their outputs
    Timer {
        id: exitTimer
        interval: 1500
        onTriggered: {
            root.log(root.failed ? "ENDED with failures" : "DONE")
            Qt.exit(root.failed ? 1 : 0)
        }
    }
}
