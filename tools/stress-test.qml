import QtQuick
import QtQuick.Controls.Basic
import Scenic

// Headless structural test harness (no rendering / no probes — runs under
// -platform offscreen). SCENIC_STRESS selects the scenario:
//   catalog  — validate every auto-discovered NodeType
//   fuzz     — random sequence of store operations, invariants after each op
//   session  — build a random graph, save/reset/load, verify it round-trips
//
// The fuzzer is seeded (SCENIC_FUZZ_SEED, default 1) so any failure is
// reproducible: it logs the seed and the exact op that broke an invariant.
ApplicationWindow {
    id: app
    visible: true; width: 320; height: 240

    readonly property string scenario: Util.environmentVariable("SCENIC_STRESS")
    readonly property int seed: Number(Util.environmentVariable("SCENIC_FUZZ_SEED") || "1")
    readonly property int ops: Number(Util.environmentVariable("SCENIC_FUZZ_OPS") || "80")

    // deterministic LCG PRNG so runs are reproducible from the seed
    property int _rng: seed
    function rnd() { app._rng = (app._rng * 1103515245 + 12345) & 0x7fffffff; return app._rng / 0x7fffffff }
    function rndInt(n) { return Math.floor(rnd() * n) }
    function pick(a) { return a[rndInt(a.length)] }
    function note(m) { console.log("[stress]", m) }
    // throw, don't only Qt.exit: exit is deferred to the event loop, so the
    // caller would keep running and could still print DONE after a FAIL.
    function fail(m) { console.log("[stress] FAIL:", m); Qt.exit(1); throw new Error(m) }

    Component.onCompleted: {
        SceneStore.init()
        // The store bookkeeping is validated against the document model
        // (Score.find/findByPath), which is independent of playback — so the
        // fuzzer runs engine-stopped by default. Rapid graph churn *during*
        // playback races the audio tick thread (a score-engine issue); opt into
        // it with SCENIC_FUZZ_PLAY=1.
        if (scenario === "session" || Util.environmentVariable("SCENIC_FUZZ_PLAY") === "1") {
            Score.play()
            NodeStore.playbackDesired = true
        }
        start()
    }

    function start() {
        note("scenario=" + scenario + " seed=" + seed)
        switch (scenario) {
        case "catalog": runCatalog(); break
        case "fuzz":    fuzzTimer.start(); break
        case "session": sessionTimer.start(); break
        default: fail("unknown scenario " + scenario)
        }
    }

    // ---- catalog integrity -------------------------------------------------
    function runCatalog() {
        let n = 0, bad = 0
        const seen = ({})
        for (const r of NodeCatalog.all) {
            n++
            const id = r.kind
            if (!id) { note("empty kind"); bad++; continue }
            if (seen[id]) { note("duplicate kind: " + id); bad++ }
            seen[id] = true
            if (["source", "destination"].indexOf(r.role) < 0) { note(id + ": bad role " + r.role); bad++ }
            if (["video", "audio", "data"].indexOf(r.mediaType) < 0) { note(id + ": bad mediaType"); bad++ }
            if (!r.label) { note(id + ": no label"); bad++ }
            // A data bridge is a socket (BridgeStore), not an engine node: it
            // binds a transport instead of a protocol/process/address.
            if (r.mediaType === "data") {
                if (!r.transport) { note(id + ": data recipe with no transport"); bad++ }
                if (r.protocol || r.process || r.addr) {
                    note(id + ": data recipe carries an engine binding"); bad++
                }
            } else if (!r.protocol && !r.process && !r.addr) {
                note(id + ": no protocol/process/addr"); bad++
            }
            // fields well-formed
            const params = {}
            for (const f of (r.fields ?? [])) {
                if (!f.key) { note(id + ": field without key"); bad++ }
                if (f.visibleWhen !== undefined && typeof f.visibleWhen !== "function") { note(id + ": bad visibleWhen"); bad++ }
                params[f.key] = f.def
            }
            // makeSettings/makeProcessData must run on defaults without throwing
            try {
                if (r.makeSettings) {
                    const s = r.makeSettings(params)
                    if (!s || typeof s !== "object") { note(id + ": makeSettings not an object"); bad++ }
                }
                if (r.makeProcessData && typeof r.makeProcessData(params) !== "string")
                    { note(id + ": makeProcessData not a string"); bad++ }
                if (r.addr && typeof r.addr("dev") !== "string") { note(id + ": addr not a string"); bad++ }
            } catch (e) { note(id + ": builder threw " + e); bad++ }
        }
        note("checked " + n + " nodes, " + bad + " problem(s)")
        if (!bad) note("DONE")
        Qt.exit(bad ? 1 : 0)
    }

    // ---- model fuzz --------------------------------------------------------
    // headless-safe kinds (no hardware, no file needed), of both media types
    // so the Gain hub, audio inlet-0 summing and the cross-media rejection
    // are exercised too.
    readonly property var srcKinds: ["videotest", "solidcolor", "sine", "audiotest"]
    readonly property var dstKinds: ["window", "shmdataout", "ndiout", "videoprobe",
                                     "audioprobe"]
    property int step: 0
    property var opLog: []

    function nodeIds(model) {
        const r = []
        for (let i = 0; i < model.count; ++i) r.push(model.get(i).nodeId)
        return r
    }
    function connKeys() { return Object.keys(MatrixStore.connections) }

    // returns "" if all invariants hold, else a description
    function invariants() {
        // 1. every reported connection has existing endpoints and is backed by
        //    a real cable in the live graph (independent of the store's cache)
        for (const k of connKeys()) {
            const parts = k.split("|"), s = parts[0], d = parts[1]
            if (!NodeStore.exists(s)) return "connection " + k + " src has no hub"
            if (!NodeStore.exists(d)) return "connection " + k + " dst has no hub"
            if (!MatrixStore.cableFor(s, d)) return "connection " + k + " has no live cable"
        }
        // 2. every listed node has a live hub
        for (const id of nodeIds(NodeStore.sources))
            if (!NodeStore.exists(id)) return "listed source " + id + " has no hub"
        for (const id of nodeIds(NodeStore.destinations))
            if (!NodeStore.exists(id)) return "listed dest " + id + " has no hub"
        // 3. a node that owns a device must actually have one, and a node that
        //    is gone must leave nothing behind
        for (const id of nodeIds(NodeStore.sources).concat(nodeIds(NodeStore.destinations))) {
            const info = NodeStore.creationInfo[id]
            if (info && info.hasDevice && Score.device(id + "_dev") === null)
                return "live node " + id + " has no device"
        }
        for (const id of NodeStore.nodeOrder) {
            if (NodeStore.exists(id)) continue
            // creationInfo is deliberately kept for removed nodes, but the
            // document objects must be gone
            if (Score.find(id + "_fx") !== null)   return "orphan fx for removed " + id
            if (Score.find(id + "_proc") !== null) return "orphan proc for removed " + id
            if (Score.device(id + "_dev") !== null) return "orphan device for removed " + id
        }
        // 4. the undo facade must agree with the engine it is a facade over
        if (HistoryStore.canUndo !== Score.canUndo())
            return "HistoryStore.canUndo disagrees with the engine"
        if (HistoryStore.canRedo !== Score.canRedo())
            return "HistoryStore.canRedo disagrees with the engine"

        // 5. mixer slot uniqueness per destination
        const bySlot = ({})
        for (const k of connKeys()) {
            const d = k.split("|")[1], slot = MatrixStore.connections[k].slot
            const kk = d + "#" + slot
            if (slot > 0 && bySlot[kk]) return "slot clash on " + d + " slot " + slot
            bySlot[kk] = true
        }
        return ""
    }

    // SCENIC_FUZZ_SAFE=1 excludes every op that tears a device down (remove,
    // reconfigure, undo/redo of a create), to tell a crash caused by device
    // teardown racing the gfx tick during playback from one caused by cable
    // churn.
    readonly property bool safeMode: Util.environmentVariable("SCENIC_FUZZ_SAFE") === "1"

    function doOp() {
        const srcs = nodeIds(NodeStore.sources)
        const dsts = nodeIds(NodeStore.destinations)
        const conns = connKeys()
        const choices = ["addSrc", "addDst", "connect", "connect"]
        if (!safeMode && srcs.length + dsts.length > 0) choices.push("remove")
        if (conns.length > 0) choices.push("disconnect")
        if (!safeMode && conns.length > 0) choices.push("reconfigure")
        if (!safeMode && HistoryStore.canUndo) choices.push("undo")
        if (!safeMode && HistoryStore.canRedo) choices.push("redo")
        choices.push("scene")
        const op = pick(choices)
        app.opLog.push(op)
        switch (op) {
        case "addSrc": NodeStore.create(NodeCatalog.recipe(pick(srcKinds))); break
        case "addDst": {
            const r = NodeCatalog.recipe(pick(dstKinds))
            const p = {}; for (const f of (r.fields ?? [])) p[f.key] = f.def
            NodeStore.create(r, r.makeSettings ? r.makeSettings(p) : undefined, undefined, undefined, p)
            break
        }
        case "remove": {
            const all = srcs.concat(dsts)
            if (all.length) NodeStore.remove(pick(all))
            break
        }
        case "connect":
            if (srcs.length && dsts.length) MatrixStore.connect(pick(srcs), pick(dsts))
            break
        case "disconnect": {
            const p = pick(conns).split("|"); MatrixStore.disconnect(p[0], p[1]); break
        }
        case "reconfigure": {
            const withDev = dsts.filter(id => {
                const info = NodeStore.creationInfo[id]
                return info && info.hasDevice && NodeCatalog.recipe(info.kind).makeSettings
            })
            if (withDev.length) {
                const id = pick(withDev), r = NodeCatalog.recipe(NodeStore.creationInfo[id].kind)
                const pr = {}
                for (const f of (r.fields ?? [])) pr[f.key] = f.def
                // Perturb one string field, so that a reconfigure that applies
                // nothing is distinguishable from one that works.
                const sf = (r.fields ?? []).find(
                    f => typeof f.def === "string" && (f.type ?? "string") !== "enum")
                if (sf) pr[sf.key] = String(pr[sf.key]) + "_r" + app.step
                NodeStore.reconfigure(id, r.makeSettings(pr), pr)
                const got = NodeStore.creationInfo[id].params
                if (sf && got && got[sf.key] !== pr[sf.key])
                    app.fail("reconfigure did not record the new params for " + id)
            }
            break
        }
        case "undo": HistoryStore.undo(); break
        case "redo": HistoryStore.redo(); break
        case "scene": {
            const r = rnd()
            if (r < 0.4) {
                SceneStore.addScene()
            } else if (r < 0.75 && SceneStore.scenes.count > 1) {
                SceneStore.activate(
                    SceneStore.scenes.get(rndInt(SceneStore.scenes.count)).sceneId)
            } else if (r < 0.9 && SceneStore.scenes.count > 1) {
                // removeScene and renameScene are checked against the result
                const n = SceneStore.scenes.count
                SceneStore.removeScene(
                    SceneStore.scenes.get(rndInt(SceneStore.scenes.count)).sceneId)
                if (SceneStore.scenes.count !== n - 1)
                    app.fail("removeScene left " + SceneStore.scenes.count
                             + " scenes, expected " + (n - 1))
            } else if (SceneStore.scenes.count > 0) {
                const i = rndInt(SceneStore.scenes.count)
                const id = SceneStore.scenes.get(i).sceneId
                const nm = "S" + app.step
                SceneStore.renameScene(id, nm)
                if (SceneStore.sceneName(id) !== nm)
                    app.fail("renameScene did not take for " + id)
            }
            break
        }
        }
    }

    Timer {
        id: fuzzTimer; interval: 60; repeat: true
        onTriggered: {
            app.step++
            app.doOp()
            const v = app.invariants()
            if (v !== "") {
                app.note("op#" + app.step + " " + app.opLog[app.opLog.length - 1])
                app.note("history: " + app.opLog.join(","))
                app.fail("invariant broken after op#" + app.step + ": " + v)
            }
            if (app.step >= app.ops) {
                fuzzTimer.stop()
                app.note("survived " + app.ops + " ops; sources=" + NodeStore.sources.count
                         + " dests=" + NodeStore.destinations.count + " conns=" + app.connKeys().length)
                // Undoing to the bottom of the stack and redoing back to where
                // we started must reproduce the whole state, not just the
                // connection count.
                //
                // Redo back to the *starting index*, not to the top: the fuzz
                // legitimately ends below the top whenever an undo is followed
                // by ops that commit nothing (connecting an already-connected
                // pair is a no-op and so does not truncate the redo branch).
                // Redoing all the way up would land on a different, equally
                // valid state.
                const before = app.connKeys().length
                const beforeState = JSON.stringify(app.fullSnapshot())
                const idx0 = Score.undoIndex()
                let guard = 0
                while (HistoryStore.canUndo && guard++ < 500) HistoryStore.undo()
                let iv = app.invariants(); if (iv !== "") app.fail("after undo-all: " + iv)
                if (Score.undoIndex() !== 0)
                    app.fail("undo-all stopped at " + Score.undoIndex())
                // the bottom of the stack is the empty document we started from
                if (app.connKeys().length !== 0 || NodeStore.sources.count !== 0
                        || NodeStore.destinations.count !== 0)
                    app.fail("undo-all left " + NodeStore.sources.count + " sources, "
                             + NodeStore.destinations.count + " dests, "
                             + app.connKeys().length + " conns")
                guard = 0
                while (Score.undoIndex() < idx0 && HistoryStore.canRedo && guard++ < 500)
                    HistoryStore.redo()
                iv = app.invariants(); if (iv !== "") app.fail("after redo-all: " + iv)
                if (Score.undoIndex() !== idx0)
                    app.fail("redo stopped at " + Score.undoIndex() + ", wanted " + idx0)
                if (app.connKeys().length !== before)
                    app.fail("undo/redo did not restore conns: " + before + " -> " + app.connKeys().length)
                const afterState = JSON.stringify(app.fullSnapshot())
                if (afterState !== beforeState)
                    app.fail("undo/redo did not restore the state:\n  before " + beforeState
                             + "\n  after  " + afterState)
                app.note("undo-all/redo-all consistent (conns=" + before + ", idx=" + idx0 + ")")
                app.note("DONE")
                Qt.exit(0)
            }
        }
    }

    // ---- session round-trip -------------------------------------------------
    property int sstep: 0
    property var snapshot: ({})
    property string nonce: ""
    property string otherScene: ""
    property string otherConns: ""
    property string geomId: ""

    // Everything a session is supposed to preserve: counts, labels, params,
    // settings, the preset blob, the node counter, the matrix order, the active
    // scene and every inactive scene's connections.
    function fullSnapshot() {
        const ids = app.nodeIds(NodeStore.sources).concat(
                    app.nodeIds(NodeStore.destinations))
        const labels = [], params = [], settings = [], presets = []
        for (const id of ids) {
            const info = NodeStore.creationInfo[id] ?? {}
            labels.push(info.label ?? "")
            params.push(JSON.stringify(info.params ?? null))
            settings.push(JSON.stringify(info.settings ?? null))
            const f = NodeStore.fx(id)
            presets.push(f ? String(Score.savePreset(f)).length : -1)
        }
        const scenes = []
        for (let i = 0; i < SceneStore.scenes.count; ++i)
            scenes.push(SceneStore.scenes.get(i).name)
        return {
            src: NodeStore.sources.count, dst: NodeStore.destinations.count,
            conns: app.connKeys().sort().join(";"),
            scenes: scenes.length, sceneNames: scenes,
            counter: NodeStore.counter, order: ids,
            labels: labels, params: params, settings: settings, presets: presets,
            active: SceneStore.activeSceneId
        }
    }
    Timer {
        id: sessionTimer; interval: 120; repeat: true
        onTriggered: {
            app.sstep++
            switch (app.sstep) {
            case 1: {
                // build a small deterministic graph
                for (let i = 0; i < 5; ++i) app.doOp()
                // ensure at least one connection exists
                if (app.connKeys().length === 0 && NodeStore.sources.count && NodeStore.destinations.count)
                    MatrixStore.connect(app.nodeIds(NodeStore.sources)[0], app.nodeIds(NodeStore.destinations)[0])
                // A second scene with a different connection set: the restore
                // path only rebuilds the active scene's cables, so an inactive
                // scene's connections need a check of their own.
                const other = SceneStore.addScene("Other")
                SceneStore.activate(other)
                if (NodeStore.sources.count && NodeStore.destinations.count)
                    MatrixStore.connect(app.nodeIds(NodeStore.sources)[0],
                                        app.nodeIds(NodeStore.destinations)[0])
                app.otherScene = other
                app.otherConns = MatrixStore.serialize().map(c => c.src + "|" + c.dst)
                                             .sort().join(";")
                SceneStore.activate(SceneStore.scenes.get(0).sceneId)
                // A nonce in a label: the graph is seed-deterministic, so a
                // save() that silently became a no-op would still "round-trip"
                // against the file the previous run left behind.
                app.nonce = "n" + app.seed + "_" + Date.now()
                {
                    const r = NodeCatalog.recipe("solidcolor")
                    const p = {}
                    for (const f of (r.fields ?? [])) p[f.key] = f.def
                    const id = NodeStore.create(
                        r, r.makeSettings ? r.makeSettings(p) : undefined,
                        app.nonce, undefined, p)
                    if (!id) app.fail("could not create the nonce node")
                }
                // A vec2 device parameter: it reads back as an {x,y} object and
                // has to go back as an array; in the wrong shape a restored
                // Video Monitor comes back as a 1x1 window although its size
                // was saved correctly.
                {
                    const r = NodeCatalog.recipe("window")
                    const id = NodeStore.create(r, r.settings, "geom")
                    if (!id) {
                        app.fail("could not create the geometry node")
                    } else {
                        app.geomId = id
                        Device.write(id + "_dev:/size", [640, 480])
                        Device.write(id + "_dev:/position", [70, 90])
                    }
                }
                app.snapshot = app.fullSnapshot()
                app.note("built src=" + app.snapshot.src + " dst=" + app.snapshot.dst
                         + " conns=" + app.connKeys().length
                         + " scenes=" + app.snapshot.scenes + " nonce=" + app.nonce)
                if (SessionStore.save("stress_roundtrip") !== true)
                    app.fail("save() reported failure")
                break
            }
            case 3:
                SessionStore.reset()
                if (NodeStore.sources.count !== 0 || app.connKeys().length !== 0)
                    app.fail("reset did not clear")
                app.note("reset ok")
                break
            case 5:
                SessionStore.load("stress_roundtrip")
                break
            case 7: {
                const now = app.fullSnapshot()
                for (const k of ["src", "dst", "conns", "scenes", "counter",
                                 "order", "labels", "params", "settings",
                                 "presets", "active"]) {
                    if (JSON.stringify(now[k]) !== JSON.stringify(app.snapshot[k]))
                        app.fail(k + " mismatch after reload:\n  before "
                                 + JSON.stringify(app.snapshot[k])
                                 + "\n  after  " + JSON.stringify(now[k]))
                }
                // The geometry has to come back as geometry: a vec2 written in
                // the wrong shape leaves the window at 1x1 while every count
                // and label above still matches.
                if (app.geomId !== "") {
                    const sz = Device.read(app.geomId + "_dev:/size")
                    const px = sz && sz.x !== undefined ? sz.x : (sz ? sz[0] : -1)
                    const py = sz && sz.y !== undefined ? sz.y : (sz ? sz[1] : -1)
                    if (Math.round(px) !== 640 || Math.round(py) !== 480)
                        app.fail("the window geometry did not survive the reload: "
                                 + "wanted 640x480, read " + px + "x" + py)
                }

                // the nonce proves we read back this run's file
                if (String(now.labels).indexOf(app.nonce) === -1)
                    app.fail("the nonce " + app.nonce + " did not survive the"
                             + " round-trip: a stale session file was loaded")
                const iv = app.invariants(); if (iv !== "") app.fail("post-load: " + iv)
                app.sstep = 7   // stay here; case 8 checks the inactive scene
                break
            }
            case 8: {
                // the other scene's cables must come back when it is activated
                SceneStore.activate(app.otherScene)
                const got = MatrixStore.serialize().map(c => c.src + "|" + c.dst)
                                       .sort().join(";")
                if (got !== app.otherConns)
                    app.fail("an inactive scene's connections were lost:\n  before "
                             + app.otherConns + "\n  after  " + got)
                app.note("round-trip OK (src=" + app.snapshot.src
                         + " dst=" + app.snapshot.dst
                         + " conns=" + app.connKeys().length
                         + ", labels/params/settings/presets/order/scenes verified)")
                app.note("DONE")
                Qt.exit(0)
            }
            }
        }
    }
}
