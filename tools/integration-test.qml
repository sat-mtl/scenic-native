import QtQuick
import QtQuick.Controls.Basic
import Scenic

// Data-validating routing integration tests. Drives the real stores
// (NodeStore / MatrixStore) exactly like the UI, routes solid-color / sine
// sources through the hub graph into GStreamer "probe" outputs that write
// JPEG frames / raw audio to files, then exits. tools/test-routing.sh checks
// the resulting files with PIL/numpy.
//
// SCENIC_IT selects the scenario. Each probe writes to a distinct file so a
// single run can capture several routing states; the checker decodes the last
// frame of each file (filesink appends, so the tail reflects the final state).
ApplicationWindow {
    id: app
    visible: true
    width: 320; height: 240

    readonly property string scenario: Util.environmentVariable("SCENIC_IT")
    property int step: 0

    function color(hex) {
        const r = NodeCatalog.recipe("solidcolor")
        return NodeStore.create(r, r.makeSettings({ color: hex }))
    }
    function sine(freq) {
        const r = NodeCatalog.recipe("sine")
        return NodeStore.create(r, r.makeSettings({ freq: freq }))
    }
    function probe(path) {
        const r = NodeCatalog.recipe("videoprobe")
        return NodeStore.create(r, r.makeSettings({ path: path }))
    }
    function aprobe(path) {
        const r = NodeCatalog.recipe("audioprobe")
        return NodeStore.create(r, r.makeSettings({ path: path }))
    }
    function note(m) { console.log("[it]", m) }

    Component.onCompleted: {
        SceneStore.init()
        Score.play()
        NodeStore.playbackDesired = true
    }

    // Longer interval: give each routing state time to push frames through the
    // Gfx readback into the probe file before the next state change.
    Timer {
        interval: 1500; repeat: true; running: true
        onTriggered: {
            app.step++
            switch (app.scenario) {
            case "single":       app.runSingle(); break
            case "mix":          app.runMix(); break
            case "remove":       app.runRemove(); break
            case "manyremove":   app.runManyRemove(); break
            case "audio":        app.runAudio(); break
            case "createall":    app.runCreateAll(); break
            case "coloradjust":  app.runColorAdjust(); break
            case "undo":         app.runUndo(); break
            case "videofile":    app.runVideoFile(); break
            case "sessionvideo": app.runSessionVideo(); break
            default: app.note("unknown scenario " + app.scenario); Qt.exit(1)
            }
        }
    }

    // Single source: solid red -> probe. Expect pure red.
    function runSingle() {
        switch (step) {
        case 1:
            color("0xFFFF0000")               // src_solidcolor_1
            probe("/tmp/it_single.jpg")       // dst_videoprobe_2
            note("connect: " + MatrixStore.connect("src_solidcolor_1", "dst_videoprobe_2"))
            break
        case 4: note("DONE"); Qt.exit(0)
        }
    }

    // Additive mixing: red + green -> one probe -> yellow; +blue -> white.
    function runMix() {
        switch (step) {
        case 1:
            color("0xFFFF0000"); color("0xFF00FF00"); color("0xFF0000FF")
            probe("/tmp/it_mix_r.jpg")        // dst 4
            probe("/tmp/it_mix_rg.jpg")       // dst 5
            probe("/tmp/it_mix_rgb.jpg")      // dst 6
            MatrixStore.connect("src_solidcolor_1", "dst_videoprobe_4")
            MatrixStore.connect("src_solidcolor_1", "dst_videoprobe_5")
            MatrixStore.connect("src_solidcolor_2", "dst_videoprobe_5")
            MatrixStore.connect("src_solidcolor_1", "dst_videoprobe_6")
            MatrixStore.connect("src_solidcolor_2", "dst_videoprobe_6")
            note("connect blue->rgb: " + MatrixStore.connect("src_solidcolor_3", "dst_videoprobe_6"))
            break
        case 4: note("DONE"); Qt.exit(0)
        }
    }

    // Remove a feed: red+green -> probe (yellow), then disconnect green -> red.
    function runRemove() {
        switch (step) {
        case 1:
            color("0xFFFF0000"); color("0xFF00FF00")
            probe("/tmp/it_remove.jpg")       // dst 3
            MatrixStore.connect("src_solidcolor_1", "dst_videoprobe_3")
            MatrixStore.connect("src_solidcolor_2", "dst_videoprobe_3")
            note("both connected (expect yellow mid-file)")
            break
        case 3:
            note("disconnect green: " + MatrixStore.disconnect("src_solidcolor_2", "dst_videoprobe_3"))
            break
        case 6: note("DONE"); Qt.exit(0)   // tail of file should be pure red
        }
    }

    // Many-to-one then remove sources entirely (node removal frees mixer slots).
    function runManyRemove() {
        switch (step) {
        case 1:
            color("0xFF800000"); color("0xFF008000"); color("0xFF000080")
            probe("/tmp/it_many.jpg")         // dst 4
            MatrixStore.connect("src_solidcolor_1", "dst_videoprobe_4")
            MatrixStore.connect("src_solidcolor_2", "dst_videoprobe_4")
            MatrixStore.connect("src_solidcolor_3", "dst_videoprobe_4")
            note("three half-bright -> ~[128,128,128]")
            break
        case 3:
            NodeStore.remove("src_solidcolor_2")   // remove green node entirely
            NodeStore.remove("src_solidcolor_3")   // remove blue node entirely
            note("removed green+blue nodes; tail should be ~[128,0,0]")
            break
        case 6: note("DONE"); Qt.exit(0)
        }
    }

    // Create every catalog recipe (except enumerated hardware ones) with dummy
    // field values, one per tick, logging before each so an abort in score's
    // settings deserialization pinpoints the offending recipe. Verifies the
    // node + hub are created and (if it has an address) the device resolves.
    property var _all: []
    function runCreateAll() {
        if (step === 1) {
            const all = NodeCatalog.sources.concat(NodeCatalog.destinations)
            for (const r of all) {
                if (r.enumerate) continue          // camera/ndiin need real hw
                _all.push(r)
            }
            note("will create " + _all.length + " recipes")
        }
        const i = step - 1
        if (i < _all.length) {
            const r = _all[i]
            const p = {}
            for (const f of (r.fields ?? []))
                p[f.key] = f.def !== undefined && f.def !== "" ? f.def
                         : (f.key === "path" ? "/tmp/scenic_clip.mp4" : "x")
            const s = r.makeSettings ? r.makeSettings(p) : undefined
            note("creating[" + i + "] " + r.kind)
            const id = NodeStore.create(r, s, r.label, undefined, p)
            const ok = id && NodeStore.hub(id)
            note("  -> " + (ok ? "OK " + id : "FAIL"))
            if (ok) NodeStore.remove(id)
        } else {
            note("DONE created " + _all.length)
            Qt.exit(0)
        }
    }

    // Live colour adjust: red source -> probe (red), then set the source's
    // colour-adjust saturation to 0 live -> the output desaturates to grey.
    property string caId: ""
    function runColorAdjust() {
        switch (step) {
        case 1:
            caId = color("0xFFFF0000")        // src_solidcolor_1
            probe("/tmp/it_ca_before.jpg")    // dst_videoprobe_2 (captures red)
            MatrixStore.connect(caId, "dst_videoprobe_2")
            note("connected red (expect red)")
            break
        case 3: {
            // set saturation=0 live on the source's colour-adjust process
            const fxp = NodeStore.fx(caId)
            const n = Score.inlets(fxp)
            for (let i = 0; i < n; ++i) {
                const p = Score.inlet(fxp, i)
                if (p && p.name === "saturation") { Score.setValue(p, 0.0); note("set saturation=0 live") }
            }
            probe("/tmp/it_ca_after.jpg")      // dst_videoprobe_3 (captures grey)
            MatrixStore.connect(caId, "dst_videoprobe_3")
            break
        }
        case 7: note("DONE"); Qt.exit(0)
        }
    }

    // Engine undo/redo through the real stores: counts must track, and the
    // routing must actually work again after redo (probe shows red).
    function counts() {
        return NodeStore.sources.count + "/" + NodeStore.destinations.count
             + " conns=" + Object.keys(MatrixStore.connections).length
    }
    function runUndo() {
        switch (step) {
        case 1:
            color("0xFFFF0000")               // src_solidcolor_1
            probe("/tmp/it_undo.jpg")         // dst_videoprobe_2
            MatrixStore.connect("src_solidcolor_1", "dst_videoprobe_2")
            note("built: " + counts())        // 1/1 conns=1
            break
        case 2: HistoryStore.undo(); note("undo connect: " + counts()); break   // conns=0
        case 3: HistoryStore.undo(); note("undo probe: " + counts()); break     // 1/0
        case 4: HistoryStore.undo(); note("undo color: " + counts()); break     // 0/0
        case 5:
            HistoryStore.redo(); HistoryStore.redo(); HistoryStore.redo()
            note("redo all: " + counts())     // 1/1 conns=1
            break
        case 6: HistoryStore.undo(); note("undo->remove node: " + counts()); break // undo connect
        case 7:
            NodeStore.remove("src_solidcolor_1")
            note("removed src: " + counts())  // 0/1
            HistoryStore.undo()
            note("undo remove: " + counts())  // 1/1 (node back)
            HistoryStore.redo(); HistoryStore.redo()  // redo the remove; the second redo is a no-op
            break
        case 9: note("DONE final=" + counts()); Qt.exit(0)
        }
    }

    // A session reload has to give back a working graph, not only the right
    // counts: loadPreset rewrites the hub's ports and drops the address
    // binding, so a restored node can have a device, a cable and the right
    // matrix cell and still carry no video. This checks pixels, not state.
    function runSessionVideo() {
        switch (step) {
        case 1:
            color("0xFF00FF00")                   // src_solidcolor_1
            probe("/tmp/it_session.jpg")          // dst_videoprobe_2
            note("connect: " + MatrixStore.connect("src_solidcolor_1", "dst_videoprobe_2"))
            break
        case 3:
            note("save: " + SessionStore.save("it_sessionvideo"))
            break
        case 4:
            SessionStore.reset()
            // the probe appends, so frames from before the reload would make
            // this pass on their own: start from no file at all
            Util.removeFile("/tmp/it_session.jpg")
            note("reset; probe file removed: " + !Util.fileExists("/tmp/it_session.jpg"))
            break
        case 5:
            note("load: " + SessionStore.load("it_sessionvideo"))
            break
        case 9:
            SessionStore.remove("it_sessionvideo")
            note("DONE")
            Qt.exit(0)
        }
    }

    // Video file: the native Video process decodes + self-loops on the root
    // interval. A 5s clip must still show content well past 5s (looping).
    function runVideoFile() {
        switch (step) {
        case 1:
            const r = NodeCatalog.recipe("filevideo")
            NodeStore.create(r, undefined, "clip", undefined,
                             { path: "/tmp/scenic_clip.mp4" })   // src_filevideo_1
            probe("/tmp/it_videofile.jpg")                       // dst_videoprobe_2
            note("route: " + MatrixStore.connect("src_filevideo_1", "dst_videoprobe_2"))
            break
        case 6: note("DONE"); Qt.exit(0)   // ~10s in: proves decode + loop
        }
    }

    // Audio: sine 440 -> audio probe. Checker verifies non-silence + ~440 Hz.
    function runAudio() {
        switch (step) {
        case 1:
            sine("440")                        // src 1
            aprobe("/tmp/it_audio.raw")        // dst 2
            note("connect: " + MatrixStore.connect("src_sine_1", "dst_audioprobe_2"))
            break
        case 4: note("DONE"); Qt.exit(0)
        }
    }
}
