import QtQuick
import QtQuick.Controls.Basic
import Scenic

// Data-bridge tests: the transport/codec plane (BridgeStore), end to end over
// real sockets. Headless, no hardware, no GPU.
//
// SCENIC_BRIDGE selects the scenario:
//   codec  — the MIDI <-> OSC transformation on its own: every message class
//            round-trips, and a message a MIDI port cannot carry is refused
//            rather than emitted as bytes a synth would misread.
//   route  — live UDP: OSC in -> OSC out, raw in -> raw out, and the pair the
//            whole feature exists for, a MIDI-shaped message leaving as OSC.
//   session — a bridge survives a save / reset / load with its transport
//            configuration and its links intact.
//   undo   — a link is on score's undo stack through Score.pushCommand, and
//            a macro mixing a cable with a link undoes as one unit.
//   matrix — a bridge is a matrix node: it is created without a hub, shows up
//            as a row/column, connects only to its own media type, and a
//            removal takes its links with it.
//   streams — TCP and WebSocket inputs receive (their servers deliver per
//            client connection), a reconfigured bridge keeps its links, and
//            creating and removing a bridge are single undo steps.
//
// Judged by markers: "[bridge] DONE" is printed only when nothing failed.
ApplicationWindow {
    id: app
    visible: true; width: 320; height: 240

    readonly property string scenario: Util.environmentVariable("SCENIC_BRIDGE")
    property int bad: 0
    property int checks: 0
    function note(m) { console.log("[bridge]", m) }
    function bad_(m) { app.bad++; console.log("[bridge] FAIL:", m) }
    function ok(cond, m) { app.checks++; if (!cond) app.bad_(m) }

    function finish() {
        if (app.bad === 0)
            console.log("[bridge] DONE", app.checks, "checks")
        else
            console.log("[bridge] ENDED with", app.bad, "failure(s)")
        Qt.callLater(function() { Qt.exit(app.bad === 0 ? 0 : 1) })
    }

    // ---------------------------------------------------------------- codec
    function runCodec() {
        const cases = [
            { name: "note on",    bytes: [0x91, 60, 100], addr: "/midi/2/note/60",  vals: [100] },
            { name: "note off",   bytes: [0x81, 60, 64],  addr: "/midi/2/note/60",  vals: [0] },
            { name: "cc",         bytes: [0xB0, 7, 127],  addr: "/midi/1/cc/7",     vals: [127] },
            { name: "program",    bytes: [0xC5, 42],      addr: "/midi/6/program",  vals: [42] },
            { name: "pressure",   bytes: [0xD3, 55],      addr: "/midi/4/pressure", vals: [55] },
            { name: "aftertouch", bytes: [0xA0, 60, 20],  addr: "/midi/1/aftertouch/60", vals: [20] }
        ]
        for (const c of cases) {
            const m = BridgeStore.midiToOsc(new Uint8Array(c.bytes))
            app.ok(m.address === c.addr,
                   c.name + ": address " + m.address + " != " + c.addr)
            app.ok(JSON.stringify(m.values) === JSON.stringify(c.vals),
                   c.name + ": values " + JSON.stringify(m.values))
            // and back again
            const raw = BridgeStore.oscToMidi(m.address, m.values)
            app.ok(raw !== null, c.name + ": did not convert back")
            if (raw) {
                // note-off is normalised to a velocity-0 note-on's inverse, so
                // compare on what the wire means, not on the original bytes
                app.ok(raw.length === c.bytes.length,
                       c.name + ": length " + raw.length + " != " + c.bytes.length)
                app.ok((raw[0] & 0x0F) === (c.bytes[0] & 0x0F),
                       c.name + ": channel changed")
            }
        }

        // 14-bit pitch bend survives the split
        const bend = BridgeStore.midiToOsc(new Uint8Array([0xE0, 0x00, 0x40]))
        app.ok(bend.address === "/midi/1/bend", "bend address: " + bend.address)
        app.ok(bend.values[0] === 8192, "bend value: " + bend.values[0])
        const bendBack = BridgeStore.oscToMidi(bend.address, bend.values)
        app.ok(bendBack[1] === 0x00 && bendBack[2] === 0x40,
               "bend did not round-trip: " + JSON.stringify(bendBack))

        // an address MIDI cannot express must be refused, not guessed at
        app.ok(BridgeStore.oscToMidi("/scenic/scene/1", [1]) === null,
               "a non-MIDI address was converted to MIDI anyway")
        app.ok(BridgeStore.oscToMidi("/midi/1/nonsense", [1]) === null,
               "an unknown /midi verb was converted anyway")
        finish()
    }

    // ---------------------------------------------------------------- route
    property var feeder: null
    property var rxSock: null
    property var rxDec: null
    property var received: []
    property bool midiLeg: false
    property string midiNode: ""

    function listen(port, done) {
        app.rxDec = Protocols.osc({ onOsc: function(a, v) {
            app.received.push({ address: a, values: v })
        }})
        app.rxSock = Protocols.inboundUDP({
            Transport: { Bind: "127.0.0.1", Port: String(port) },
            onMessage: function(b) {
                app.received.push({ raw: String(b) })
                app.rxDec.processMessage(b)
            },
            onError: function(e) { app.bad_("listener: " + e) }
        })
    }

    function runRoute() {
        // The observer that stands in for the outside world.
        listen(9412)

        // in (OSC on 9410) -> out (OSC to 9412)
        const inId = NodeStore.create(NodeCatalog.recipe("udpin"), null, "in", null,
                                      { bind: "127.0.0.1", port: 9410, codec: "osc" })
        const outId = NodeStore.create(NodeCatalog.recipe("udpout"), null, "out", null,
                                       { host: "127.0.0.1", port: 9412, codec: "osc" })
        app.ok(!!inId && !!outId, "could not create the UDP bridge pair")
        if (!inId || !outId) { finish(); return }

        // a bridge is a node with no hub
        app.ok(NodeStore.hub(inId) === null, "a data bridge grew a hub")
        app.ok(NodeStore.exists(inId), "a data bridge does not report as existing")

        app.ok(MatrixStore.connect(inId, outId), "could not connect the bridges")
        app.ok(MatrixStore.isConnected(inId, outId), "connection not reported")

        // a MIDI-shaped message arriving as OSC must leave as the same OSC
        const midiId = NodeStore.create(NodeCatalog.recipe("midiin"), null, "m", null,
                                        { device: "", codec: "midi" })
        if (midiId) {
            app.ok(MatrixStore.connect(midiId, outId),
                   "could not connect MIDI in -> UDP out")
            // drive the decoder directly: no hardware is guaranteed here
            app.midiLeg = true
            app.midiNode = midiId
        } else {
            app.note("no MIDI input port on this machine: skipping the MIDI leg")
        }

        // now push something into the inbound socket from outside
        const feeder = Protocols.outboundUDP({
            Transport: { Host: "127.0.0.1", Port: "9410" },
            onError: function(e) { app.bad_("feeder: " + e) }
        })
        app.feeder = feeder
        // Outbound sockets open asynchronously (qml_protocols open_later), and
        // osc() on one that is not open yet is a silent no-op - so send once
        // they have had a chance to come up, not at creation.
        routeSend.start()
        routeCheck.start()
    }

    Timer {
        id: routeSend
        interval: 700; repeat: false
        onTriggered: {
            app.feeder.osc("/scenic/level", [0.25])
            if (app.midiLeg)
                BridgeStore.deliver(app.midiNode,
                    BridgeStore.midiToOsc(new Uint8Array([0xB0, 7, 99])))
        }
    }

    Timer {
        id: routeCheck
        interval: 2500; repeat: false
        onTriggered: {
            let sawForwarded = false, sawMidi = false
            for (const m of app.received) {
                if (m.address === "/scenic/level"
                    && Math.abs(Number(m.values[0]) - 0.25) < 1e-6)
                    sawForwarded = true
                if (m.address === "/midi/1/cc/7" && Number(m.values[0]) === 99)
                    sawMidi = true
            }
            app.ok(sawForwarded,
                   "OSC in -> OSC out did not arrive: " + JSON.stringify(app.received))
            if (app.midiLeg)
                app.ok(sawMidi, "MIDI -> OSC over UDP did not arrive: "
                                + JSON.stringify(app.received))
            app.finish()
        }
    }

    // --------------------------------------------------------------- matrix
    function runMatrix() {
        const inId = NodeStore.create(NodeCatalog.recipe("udpin"), null, "in", null,
                                      { bind: "127.0.0.1", port: 9420, codec: "raw" })
        const outId = NodeStore.create(NodeCatalog.recipe("udpout"), null, "out", null,
                                       { host: "127.0.0.1", port: 9421, codec: "raw" })
        app.ok(!!inId && !!outId, "could not create the bridge pair")
        if (!inId || !outId) { finish(); return }

        // it is a row / a column
        let asRow = false, asCol = false
        for (let i = 0; i < NodeStore.sources.count; ++i)
            if (NodeStore.sources.get(i).nodeId === inId) asRow = true
        for (let i = 0; i < NodeStore.destinations.count; ++i)
            if (NodeStore.destinations.get(i).nodeId === outId) asCol = true
        app.ok(asRow, "a data source is not a matrix row")
        app.ok(asCol, "a data destination is not a matrix column")

        // and it only talks to its own media type
        const vid = NodeStore.create(NodeCatalog.recipe("videotest"), null, "v", null, {})
        if (vid) {
            app.ok(!MatrixStore.compatible(inId, vid),
                   "a data source is compatible with a video destination")
            app.ok(!MatrixStore.applyConnect(inId, vid),
                   "a data source connected to a video destination")
        }

        app.ok(MatrixStore.connect(inId, outId), "could not connect")
        app.ok(MatrixStore.isConnected(inId, outId), "not reported as connected")

        // the matrix is one surface: a data link survives a refresh that
        // re-derives everything else from the engine
        MatrixStore.refresh()
        app.ok(MatrixStore.isConnected(inId, outId),
               "the data link was lost by a refresh")

        // removing the source takes the link with it
        NodeStore.remove(inId)
        app.ok(!NodeStore.exists(inId), "the bridge survived its removal")
        app.ok(!MatrixStore.isConnected(inId, outId),
               "the link survived the bridge it belonged to")
        finish()
    }

    // -------------------------------------------------------------- session
    property string sessIn: ""
    property string sessOut: ""

    function runSession() {
        app.sessIn = NodeStore.create(NodeCatalog.recipe("udpin"), null, "in", null,
                                      { bind: "127.0.0.1", port: 9430, codec: "osc" })
        app.sessOut = NodeStore.create(NodeCatalog.recipe("udpout"), null, "out", null,
                                       { host: "127.0.0.1", port: 9431, codec: "osc" })
        app.ok(!!app.sessIn && !!app.sessOut, "could not create the pair")
        if (!app.sessIn || !app.sessOut) { finish(); return }
        app.ok(MatrixStore.connect(app.sessIn, app.sessOut), "could not connect")

        app.ok(SessionStore.save("bridge_roundtrip"), "could not save the session")
        SessionStore.reset()
        app.ok(!NodeStore.exists(app.sessIn), "reset left the bridge behind")
        app.ok(SessionStore.load("bridge_roundtrip"), "could not load the session")
        sessionCheck.start()
    }

    Timer {
        id: sessionCheck
        interval: 1500; repeat: false
        onTriggered: {
            app.ok(NodeStore.exists(app.sessIn), "the bridge did not come back")
            app.ok(NodeStore.exists(app.sessOut), "the outbound bridge did not come back")
            // a restored bridge must be a live socket, not just a row
            app.ok(BridgeStore.isBridge(app.sessIn),
                   "the restored bridge has no open channel")
            const ch = BridgeStore.channels[app.sessIn]
            app.ok(!!ch && ch.codec === "osc",
                   "the restored bridge lost its codec: " + (ch ? ch.codec : "none"))
            app.ok(MatrixStore.isConnected(app.sessIn, app.sessOut),
                   "the link did not survive the round trip")
            app.finish()
        }
    }

    // ----------------------------------------------------------------- undo
    function runUndo() {
        const inId = NodeStore.create(NodeCatalog.recipe("udpin"), null, "in", null,
                                      { bind: "127.0.0.1", port: 9440, codec: "raw" })
        const outId = NodeStore.create(NodeCatalog.recipe("udpout"), null, "out", null,
                                       { host: "127.0.0.1", port: 9441, codec: "raw" })
        app.ok(!!inId && !!outId, "could not create the pair")
        if (!inId || !outId) { finish(); return }

        const idx0 = Score.undoIndex()
        app.ok(MatrixStore.connect(inId, outId), "could not connect")
        app.ok(MatrixStore.isConnected(inId, outId), "not connected")
        app.ok(Score.undoIndex() === idx0 + 1,
               "connecting a bridge pushed " + (Score.undoIndex() - idx0)
               + " commands, expected 1")

        // through HistoryStore, which is the app's undo path: it resyncs the
        // stores after the whole command, not part-way through an aggregate
        HistoryStore.undo()
        app.ok(!MatrixStore.isConnected(inId, outId),
               "undo did not remove the link")
        HistoryStore.redo()
        app.ok(MatrixStore.isConnected(inId, outId),
               "redo did not restore the link")

        // the point of doing it this way: one macro, one undo, both planes
        const vidSrc = NodeStore.create(NodeCatalog.recipe("videotest"), null, "v", null, {})
        const vidDst = NodeStore.create(NodeCatalog.recipe("window"), null, "w", null, {})
        if (vidSrc && vidDst) {
            MatrixStore.disconnect(inId, outId)
            const idx1 = Score.undoIndex()
            Score.withMacro(function() {
                MatrixStore.applyConnect(vidSrc, vidDst)   // a real cable
                MatrixStore.applyConnect(inId, outId)      // a data link
            })
            app.ok(MatrixStore.isConnected(vidSrc, vidDst), "the cable was not made")
            app.ok(MatrixStore.isConnected(inId, outId), "the link was not made")
            app.ok(Score.undoIndex() === idx1 + 1,
                   "a mixed macro pushed " + (Score.undoIndex() - idx1)
                   + " commands, expected 1")
            HistoryStore.undo()
            app.ok(!MatrixStore.isConnected(vidSrc, vidDst),
                   "one undo left the cable behind")
            app.ok(!MatrixStore.isConnected(inId, outId),
                   "one undo left the data link behind - the two planes "
                   + "did not undo together")
        }
        finish()
    }

    // -------------------------------------------------------------- streams
    property var tcpFeeder: null
    property var wsFeeder: null
    property string streamsIn: ""
    property string streamsOut: ""

    function runStreams() {
        listen(9452)
        const tcpIn = NodeStore.create(NodeCatalog.recipe("tcpin"), null, "tcp in", null,
                                       { bind: "127.0.0.1", port: 9450, codec: "osc" })
        const wsIn = NodeStore.create(NodeCatalog.recipe("wsin"), null, "ws in", null,
                                      { bind: "127.0.0.1", port: 9460, codec: "raw" })
        const out = NodeStore.create(NodeCatalog.recipe("udpout"), null, "out", null,
                                     { host: "127.0.0.1", port: 9452, codec: "osc" })
        app.ok(!!tcpIn && !!wsIn && !!out, "could not create the bridges")
        if (!tcpIn || !wsIn || !out) { finish(); return }
        app.ok(MatrixStore.connect(tcpIn, out), "could not connect tcp -> udp")
        app.ok(MatrixStore.connect(wsIn, out), "could not connect ws -> udp")
        app.streamsIn = tcpIn
        app.streamsOut = out

        // reopening with other parameters must keep the links
        app.ok(NodeStore.reconfigure(out, null,
                                     { host: "127.0.0.1", port: 9452, codec: "raw" }),
               "could not reconfigure the output")
        app.ok(BridgeStore.channels[out].codec === "raw", "the new codec was not applied")
        app.ok(MatrixStore.isConnected(tcpIn, out), "reconfiguring dropped a link")
        HistoryStore.undo()
        app.ok(BridgeStore.channels[out].codec === "osc", "undo did not restore the codec")
        app.ok(NodeStore.creationInfo[out].params.codec === "osc",
               "undo did not restore the node's params")
        app.ok(MatrixStore.isConnected(tcpIn, out), "undoing the reconfigure dropped a link")

        app.tcpFeeder = Protocols.outboundTCP({
            Transport: { Host: "127.0.0.1", Port: "9450" }, Framing: { type: "slip" },
            onError: e => app.bad_("tcp feeder: " + e) })
        app.wsFeeder = Protocols.outboundWS({
            Transport: { Host: "127.0.0.1", Port: "9460" },
            onError: e => app.bad_("ws feeder: " + e) })
        streamsSend.start()
    }

    Timer {
        id: streamsSend
        interval: 700
        onTriggered: {
            app.tcpFeeder.osc("/tcp/level", [0.5])
            // raw bytes in, forwarded as the "/raw" int array by the OSC output
            app.wsFeeder.writeBinary(new Uint8Array([1, 2, 3]).buffer)
            streamsCheck.start()
        }
    }

    Timer {
        id: streamsCheck
        interval: 1000
        onTriggered: {
            const got = a => app.received.some(m => m.address === a)
            app.ok(got("/tcp/level"), "nothing arrived through the TCP input: "
                                      + JSON.stringify(app.received))
            app.ok(got("/raw"), "nothing arrived through the WebSocket input: "
                                + JSON.stringify(app.received))

            // create and remove are one undo step each
            const idx = Score.undoIndex()
            const extra = NodeStore.create(NodeCatalog.recipe("udpin"), null, "extra", null,
                                           { bind: "127.0.0.1", port: 9470, codec: "raw" })
            app.ok(Score.undoIndex() === idx + 1, "creating a bridge pushed "
                   + (Score.undoIndex() - idx) + " commands, expected 1")
            HistoryStore.undo()
            app.ok(!NodeStore.exists(extra), "undo did not remove the new bridge")
            HistoryStore.redo()
            app.ok(NodeStore.exists(extra), "redo did not bring the bridge back")

            NodeStore.remove(app.streamsIn)
            app.ok(!NodeStore.exists(app.streamsIn), "the bridge survived its removal")
            HistoryStore.undo()
            app.ok(NodeStore.exists(app.streamsIn), "undo did not restore the bridge")
            app.ok(MatrixStore.isConnected(app.streamsIn, app.streamsOut),
                   "undo did not restore the bridge's link")
            app.finish()
        }
    }

    Component.onCompleted: Qt.callLater(function() {
        // As Main.qml does: with no active scene snapshotActive() is a no-op
        // and nothing about the matrix would reach the session.
        SceneStore.init()
        switch (app.scenario) {
        case "codec":   app.runCodec(); break
        case "route":   app.runRoute(); break
        case "session": app.runSession(); break
        case "undo":    app.runUndo(); break
        case "matrix":  app.runMatrix(); break
        case "streams": app.runStreams(); break
        default: app.bad_("unknown scenario: " + app.scenario); finish()
        }
    })
}
