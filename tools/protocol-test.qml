import QtQuick
import QtQuick.Controls.Basic
import Scenic

// Protocol / node-catalog conformance tests. Headless, no hardware, no GPU.
//
// SCENIC_PROTO selects the scenario:
//   schema  — static conformance of every recipe: settings key sets against
//             what score's C++ readers actually consume, address conventions,
//             GStreamer pipeline invariants, field well-formedness.
//   graph   — routing rules that need a live graph: the 8-input mixer limit and
//             slot reuse, media-type gating, fan-out cleanup when a source is
//             removed, and that a reconfigure keeps a node's cables.
//   create  — instantiate every non-enumerated recipe in the engine and assert
//             it really came up (hub, device, bound address) and leaves no
//             residue when removed. This is the sweep that catches a settings
//             object score cannot digest.
//
// Judged by markers: FAIL lines are printed per problem and "[proto] DONE" is
// printed only when nothing failed, so DONE can never follow a FAIL.
ApplicationWindow {
    id: app
    visible: true; width: 320; height: 240

    readonly property string scenario: Util.environmentVariable("SCENIC_PROTO")
    property int bad: 0
    property int checks: 0

    function note(m) { console.log("[proto]", m) }
    function bad_(m) { app.bad++; console.log("[proto] FAIL:", m) }
    function ok(cond, m) { app.checks++; if (!cond) app.bad_(m) }

    // ---- ground truth ------------------------------------------------------
    // The exact keys each device's JSON reader consumes, extracted from the
    // score sources (parseJsonField(...)/obj[...] in the *Device.cpp readers).
    // A key the reader never looks at is a silent no-op, so extras fail too.
    readonly property var schemas: ({
        "gstreamer":     ["Pipeline","Width","Height","Rate","AudioChannels","InputTransfer"],
        "libav":         ["Direction","Path","Width","Height","Rate","AudioChannels","Threads",
                          "AudioEncoderShort","AudioEncoderLong","AudioSmpFmt","AudioSampleRate",
                          "VideoEncoderShort","VideoEncoderLong","VideoRenderPixFmt",
                          "VideoConvertedPixFmt","Muxer","MuxerLong","Options","InputTransfer"],
        "windowCapture": ["Mode","WindowTitle","WindowId","ScreenId","ScreenName",
                          "RegionX","RegionY","RegionW","RegionH","FPS"],
        "shmdataIn":     ["Path"],
        "spoutIn":       ["Path"],
        "spoutOut":      ["Path","Width","Height","Rate"],
        "syphonIn":      ["Path"],
        "syphonOut":     ["Path","Width","Height","Rate"],
        "pipewireIn":    ["Path"],
        "pipewireOut":   ["Path","Width","Height","Rate"],
        "sh4ltIn":       ["Path"],
        "shmdataOut":    ["Path","Width","Height","Rate"],
        "sh4ltOut":      ["Path","Width","Height","Rate"],
        // Ndi's reader also looks at Format/ColorSpace, but guards those two;
        // the first four are raw obj[...] accesses and are mandatory.
        "ndiOut":        ["Path","Width","Height","Rate"]
    })
    readonly property var schemaOptional: ({ "ndiOut": ["Format","ColorSpace"] })
    // Devices whose reader tolerates an entirely empty settings object.
    readonly property var schemaFree: ["window"]
    // Numeric keys: a number passed as a string is silently ignored by
    // parseJsonField, so the type matters as much as the key.
    readonly property var numericKeys: ["Width","Height","Rate","AudioChannels","InputTransfer",
                                        "Direction","Threads","AudioSampleRate","Mode","WindowId",
                                        "ScreenId","RegionX","RegionY","RegionW","RegionH","FPS"]

    function protocolName(uuid) {
        for (const k in Uuids)
            if (Uuids[k] === uuid) return k
        return ""
    }
    function defaultsOf(r) {
        const p = {}
        for (const f of (r.fields ?? [])) p[f.key] = f.def
        return p
    }
    function settingsOf(r) {
        if (r.settings !== null && r.settings !== undefined) return r.settings
        if (r.makeSettings) return r.makeSettings(defaultsOf(r))
        return null
    }

    Component.onCompleted: {
        SceneStore.init()
        note("scenario=" + scenario)
        switch (scenario) {
        case "schema": runSchema(); break
        case "create": Score.play(); NodeStore.playbackDesired = true
                       createTimer.start(); break
        case "graph":  Score.play(); NodeStore.playbackDesired = true
                       graphTimer.start(); break
        default: app.bad_("unknown scenario " + scenario); finish()
        }
    }

    function finish() {
        note("checked " + app.checks + " assertions, " + app.bad + " problem(s)")
        if (app.bad === 0) note("DONE")
        Qt.exit(app.bad ? 1 : 0)
    }

    // ================= schema / static conformance =========================
    function runSchema() {
        const seenKinds = ({})
        for (const r of NodeCatalog.all) {
            const k = r.kind
            // --- catalog integrity ---
            app.ok(/^[a-z0-9_]+$/.test(k), "kind not [a-z0-9_]: " + k)
            app.ok(!seenKinds[k], "duplicate kind: " + k)
            seenKinds[k] = true
            app.ok(["source","destination"].indexOf(r.role) >= 0, k + ": bad role")
            app.ok(["video","audio","data"].indexOf(r.mediaType) >= 0, k + ": bad mediaType")
            app.ok(!!r.label, k + ": no label")

            // --- data bridges ---
            // A bridge is a socket: BridgeStore opens it, so it must declare a
            // transport and must not carry any engine binding, or NodeStore
            // would take the device path and build a hub for it.
            const isBridge = r.mediaType === "data"
            if (isBridge) {
                app.ok(["udp","tcp","ws","serial","midi"].indexOf(r.transport) >= 0,
                       k + ": data recipe with unknown transport '" + r.transport + "'")
                app.ok(!r.protocol && !r.process,
                       k + ": data recipe carries an engine binding")
                app.ok(!r.addr, k + ": data recipe carries an address")
                app.ok(["raw","osc","midi"].indexOf(r.defaultCodec) >= 0,
                       k + ": data recipe with unknown default codec")
            } else {
                app.ok(!r.transport || r.transport === "",
                       k + ": non-data recipe declares a transport")
            }

            // --- device / process exclusivity ---
            const hasProto = !!(r.protocol && r.protocol !== "")
            const hasProc = !!(r.process && r.process !== "")
            app.ok(!(hasProto && hasProc), k + ": both protocol and process")
            if (hasProc) {
                app.ok(!r.makeSettings && (r.settings === null || r.settings === undefined),
                       k + ": process recipe carries device settings")
                // either form is valid, mirroring NodeStore.applyCreate
                const pd = r.makeProcessData ? r.makeProcessData(defaultsOf(r))
                                             : (r.processData ?? "")
                app.ok(typeof pd === "string", k + ": process data is not a string")
            }
            if (hasProto)
                app.ok(!!r.addr && r.addr("D") !== "", k + ": device recipe with no addr")

            checkFields(r)
            if (hasProto) { checkSettings(r); checkAddr(r); checkPipeline(r) }
        }
        // Spout is Windows-only and Syphon macOS-only: NodeCatalog refuses to
        // register a recipe whose protocol this OS does not have, so the count
        // matches the files only after those are taken out.
        const extra = Util.environmentVariable("SCENIC_NODE_PATH")
        const files = Util.listFiles(
            Util.urlToLocalFile(Qt.resolvedUrl("../qml/Scenic/Nodes")), "*.qml")
            .concat(extra !== "" ? Util.listFiles(extra, "*.qml") : [])
        let offPlatform = 0
        for (const f of files) {
            const base = f.split("/").pop()
            if (Qt.platform.os !== "windows" && base.indexOf("Spout") === 0) offPlatform++
            if (Qt.platform.os !== "osx" && base.indexOf("Syphon") === 0) offPlatform++
        }
        app.ok(NodeCatalog.all.length === files.length - offPlatform,
               "NodeCatalog loaded " + NodeCatalog.all.length + " recipes but there are "
               + files.length + " files (" + offPlatform + " off-platform)"
               + " (a file failed Qt.createComponent)")
        checkOrder(NodeCatalog.sources, "sources")
        checkOrder(NodeCatalog.destinations, "destinations")
        finish()
    }

    function checkOrder(list, what) {
        const seen = ({})
        for (let i = 0; i < list.length; ++i) {
            const o = list[i].order
            app.ok(!seen[o], what + ": duplicate order " + o + " (" + list[i].kind + ")")
            seen[o] = true
        }
    }

    function checkFields(r) {
        const keys = ({})
        for (const f of (r.fields ?? [])) {
            app.ok(!!f.key, r.kind + ": field with no key")
            app.ok(!keys[f.key], r.kind + ": duplicate field key " + f.key)
            keys[f.key] = true
            app.ok(f.def !== undefined, r.kind + "." + f.key + ": no default")
            const t = f.type ?? (f.file ? "file" : "string")
            app.ok(["string","int","float","bool","enum","vec2","file","savefile"].indexOf(t) >= 0,
                   r.kind + "." + f.key + ": bad type " + t)
            if (t === "enum") {
                app.ok(!!f.options && f.options.length > 0,
                       r.kind + "." + f.key + ": enum without options")
                const vals = (f.options ?? []).map(o => o.value)
                app.ok(vals.indexOf(f.def) >= 0,
                       r.kind + "." + f.key + ": default not among options")
            }
            if (t === "int" || t === "float")
                app.ok(f.min !== undefined && f.max !== undefined && f.min < f.max,
                       r.kind + "." + f.key + ": numeric field without a usable min/max"
                       + " (FieldEditor would give it a 0..1 slider)")
            if (f.visibleWhen !== undefined)
                app.ok(typeof f.visibleWhen === "function",
                       r.kind + "." + f.key + ": visibleWhen is not a function")
        }
        // visibleWhen must be total over every enum combination
        const enums = (r.fields ?? []).filter(f => (f.type === "enum"))
        if (enums.length === 1) {
            for (const opt of enums[0].options) {
                const vals = defaultsOf(r)
                vals[enums[0].key] = opt.value
                for (const f of r.fields) {
                    if (!f.visibleWhen) continue
                    let res
                    try { res = f.visibleWhen(vals) }
                    catch (e) { app.bad_(r.kind + "." + f.key + ": visibleWhen threw on "
                                         + enums[0].key + "=" + opt.value + ": " + e); continue }
                    app.ok(typeof res === "boolean",
                           r.kind + "." + f.key + ": visibleWhen did not return a boolean")
                }
            }
        }
    }

    function checkSettings(r) {
        const proto = protocolName(r.protocol)
        const s = settingsOf(r)
        if (r.enumerate) {
            app.ok(s === null, r.kind + ": enumerated recipe should carry no static settings")
            return
        }
        app.ok(s !== null, r.kind + ": device recipe with no settings")
        if (s === null) return
        if (app.schemaFree.indexOf(proto) >= 0) return

        const want = app.schemas[proto]
        if (!want) { app.bad_(r.kind + ": no schema known for protocol " + proto); return }
        const opt = app.schemaOptional[proto] ?? []
        const got = Object.keys(s)

        for (const key of want)
            app.ok(got.indexOf(key) >= 0,
                   r.kind + ": settings missing required key '" + key + "'")
        for (const key of got)
            app.ok(want.indexOf(key) >= 0 || opt.indexOf(key) >= 0,
                   r.kind + ": settings has key '" + key + "' the " + proto
                   + " reader never looks at (typo?)")

        for (const key of got) {
            const v = s[key]
            if (app.numericKeys.indexOf(key) >= 0)
                app.ok(typeof v === "number" && isFinite(v),
                       r.kind + "." + key + ": must be a finite number, got "
                       + typeof v + " (" + v + ")")
            else if (key === "Options")
                app.ok(Array.isArray(v) || (v && v.length !== undefined),
                       r.kind + ".Options: must be an array of [key,value] pairs")
            else
                app.ok(typeof v === "string", r.kind + "." + key + ": must be a string")
        }

        // Settings must survive the session round-trip unchanged.
        let rt
        try { rt = JSON.parse(JSON.stringify(s)) }
        catch (e) { app.bad_(r.kind + ": settings is not JSON-serialisable: " + e); return }
        app.ok(JSON.stringify(rt) === JSON.stringify(s),
               r.kind + ": settings does not survive a JSON round-trip"
               + " (session save/load would lose it)")
        app.ok(JSON.stringify(rt) !== "{}",
               r.kind + ": settings serialises to {} — the session would restore a dead device")
    }

    function checkAddr(r) {
        const proto = protocolName(r.protocol)
        const a = r.addr("D")
        app.ok(/^D:(\/[A-Za-z0-9_~(). -]+)*\/?$/.test(a) && a !== "D:",
               r.kind + ": address '" + a + "' is not a parseable device address")
        const rootTexture = ["camera","ndiIn","ndiOut","shmdataIn","shmdataOut",
                             "sh4ltIn","sh4ltOut","window","windowCapture"]
        if (rootTexture.indexOf(proto) >= 0)
            app.ok(a === "D:/", r.kind + ": " + proto
                   + " exposes its texture at the device root, expected 'D:/' got '" + a + "'")
        else if (proto === "libav")
            app.ok(a === "D:/Video", r.kind + ": libav output address should be 'D:/Video', got '" + a + "'")
        else if (proto === "gstreamer") {
            if (r.role === "destination") {
                const want = r.mediaType === "audio" ? "D:/Audio" : "D:/Video"
                app.ok(a === want, r.kind + ": GStreamer output address should be '"
                       + want + "' (capitalised), got '" + a + "'")
            } else {
                const s = settingsOf(r)
                const m = /appsink[^!]*\bname=([A-Za-z0-9_]+)/.exec(s ? s.Pipeline : "")
                if (m) app.ok(a === "D:/" + m[1],
                              r.kind + ": input address should match the appsink name '"
                              + m[1] + "', got '" + a + "'")
            }
        }
    }

    function checkPipeline(r) {
        if (protocolName(r.protocol) !== "gstreamer") return
        const s = settingsOf(r)
        if (!s) return
        const p = s.Pipeline
        app.ok(typeof p === "string" && p.length > 0, r.kind + ": empty Pipeline")
        if (typeof p !== "string") return

        const isOut = p.indexOf("appsrc") >= 0
        app.ok(isOut === (r.role === "destination"),
               r.kind + ": pipeline has " + (isOut ? "appsrc" : "no appsrc")
               + " but role is " + r.role
               + " (score decides input vs output by the presence of appsrc)")

        const srcs = p.match(/appsrc[^!]*\bname=([A-Za-z0-9_]+)/g) ?? []
        const sinks = p.match(/appsink[^!]*\bname=([A-Za-z0-9_]+)/g) ?? []
        if (isOut) {
            app.ok(srcs.length === 1, r.kind + ": expected exactly one named appsrc")
            const n = /name=([A-Za-z0-9_]+)/.exec(srcs[0] ?? "")
            if (n) app.ok(n[1] === r.mediaType, r.kind + ": appsrc is named '" + n[1]
                          + "' but mediaType is " + r.mediaType)
            // score announces the engine's floats at the engine's rate on the
            // audio appsrc: a pipeline pinning any other format or rate right
            // after it cannot negotiate, so it must convert and resample first.
            if (r.mediaType === "audio")
                app.ok(/appsrc[^!]*!\s*audioconvert\s*!\s*audioresample\b/.test(p),
                       r.kind + ": the audio appsrc must be followed by"
                       + " audioconvert ! audioresample, got '" + p + "'")
        } else {
            app.ok(sinks.length === 1, r.kind + ": expected exactly one named appsink")
            const n = /name=([A-Za-z0-9_]+)/.exec(sinks[0] ?? "")
            if (n) app.ok(n[1] === r.mediaType, r.kind + ": appsink is named '" + n[1]
                          + "' but mediaType is " + r.mediaType)
            if (r.mediaType === "audio")
                app.ok(/format=F32LE/.test(p), r.kind
                       + ": audio input must declare format=F32LE (the ring buffer takes floats)")
            else
                app.ok(/format=RGBA/.test(p), r.kind + ": video input must declare format=RGBA")
        }
        // balanced quoting: an unbalanced quote makes gst_parse_launch fail
        app.ok((p.split('"').length - 1) % 2 === 0, r.kind + ": unbalanced quotes in Pipeline")
    }

    // ================= live creation sweep =================================
    // Every non-enumerated recipe is swept, including those that wait for a
    // peer. An SRT listener with no listen_timeout blocks in avio_open forever
    // and freezes the engine with it, so the recipe's default URI carries one
    // and SRT comes up in about 5 s; RTMP and the WebRTC nodes come up in well
    // under a second with no signaller running.
    property var todo: []
    property int idx: 0
    Timer {
        id: createTimer; interval: 150; repeat: true
        onTriggered: {
            if (app.idx === 0 && app.todo.length === 0) {
                app.todo = NodeCatalog.all.filter(r => !r.enumerate)
                app.note("sweeping " + app.todo.length + " recipes")
            }
            if (app.idx >= app.todo.length) { createTimer.stop(); app.finish(); return }
            app.sweepOne(app.todo[app.idx])
            app.idx++
        }
    }

    function sweepOne(r) {
        const params = defaultsOf(r)
        let id = null
        try {
            id = NodeStore.create(r, r.makeSettings ? r.makeSettings(params) : undefined,
                                  undefined, undefined, params)
        } catch (e) { app.bad_(r.kind + ": create threw " + e); return }

        app.checks++
        if (!id) { app.bad_(r.kind + ": create returned no id"); return }
        app.ok(NodeStore.exists(id), r.kind + ": no hub after create")

        // devices live in the device tree, not the document model: Score.device,
        // not Score.find
        if (r.protocol && r.protocol !== "")
            app.ok(Score.device(id + "_dev") !== null,
                   r.kind + ": hasDevice recipe but no '" + id + "_dev' device")
        if (r.process && r.process !== "")
            app.ok(Score.find(id + "_proc") !== null, r.kind + ": no process after create")

        NodeStore.remove(id)
        app.ok(Score.find(id + "_hub") === null, r.kind + ": hub survived removal")
        app.ok(Score.find(id + "_fx") === null, r.kind + ": fx survived removal")
        app.ok(Score.find(id + "_proc") === null, r.kind + ": process survived removal")
        if (r.protocol && r.protocol !== "")
            app.ok(Score.device(id + "_dev") === null,
                   r.kind + ": device leaked — '" + id + "_dev' survived removal")
    }

    // ================= graph / routing rules ===============================
    property int gstep: 0
    property var gsrcs: []
    property var gdst: ""
    Timer {
        id: graphTimer; interval: 250; repeat: true
        onTriggered: {
            app.gstep++
            try { app.graphStep(app.gstep) }
            catch (e) { app.bad_("graph step " + app.gstep + " threw " + e)
                        graphTimer.stop(); app.finish() }
        }
    }

    function mk(kind) {
        const r = NodeCatalog.recipe(kind)
        const p = defaultsOf(r)
        return NodeStore.create(r, r.makeSettings ? r.makeSettings(p) : undefined,
                                undefined, undefined, p)
    }

    function graphStep(n) {
        switch (n) {
        case 1: {
            // a video destination hub is an 8-input mixer; make 9 sources for it
            for (let i = 0; i < 9; ++i) app.gsrcs.push(mk("solidcolor"))
            app.gdst = mk("videoprobe")
            app.ok(app.gsrcs.every(id => !!id) && !!app.gdst,
                   "could not build the 9x1 fixture")
            break
        }
        case 2: {
            // 1..8 must connect, each into its own mixer inlet
            const slots = ({})
            for (let i = 0; i < 8; ++i) {
                app.ok(MatrixStore.connect(app.gsrcs[i], app.gdst) === true,
                       "connection " + (i + 1) + " of 8 was refused")
                const e = MatrixStore.connections[app.gsrcs[i] + "|" + app.gdst]
                app.ok(!!e, "connection " + (i + 1) + " left no entry")
                if (e) {
                    app.ok(e.slot >= 1 && e.slot <= 8, "slot out of range: " + e.slot)
                    app.ok(!slots[e.slot], "slot " + e.slot + " handed out twice")
                    slots[e.slot] = true
                }
            }
            app.ok(Object.keys(slots).length === 8, "expected 8 distinct slots")
            // the 9th must be refused, and must not leave a cable behind
            const before = Object.keys(MatrixStore.connections).length
            app.ok(MatrixStore.connect(app.gsrcs[8], app.gdst) === false,
                   "a 9th source was accepted into an 8-input mixer")
            app.ok(Object.keys(MatrixStore.connections).length === before,
                   "the refused 9th connection still created a cable")
            break
        }
        case 3: {
            // free one inlet; the next connection must reuse exactly that slot
            const victim = app.gsrcs[3]
            const freed = MatrixStore.connections[victim + "|" + app.gdst].slot
            MatrixStore.disconnect(victim, app.gdst)
            app.ok(!MatrixStore.isConnected(victim, app.gdst), "disconnect did nothing")
            app.ok(MatrixStore.connect(app.gsrcs[8], app.gdst) === true,
                   "could not connect after freeing an inlet")
            const e = MatrixStore.connections[app.gsrcs[8] + "|" + app.gdst]
            app.ok(e && e.slot === freed,
                   "expected the freed slot " + freed + " to be reused, got "
                   + (e ? e.slot : "none"))
            break
        }
        case 4: {
            // media types must not cross
            const a = mk("sine")
            const ap = mk("audioprobe")
            app.ok(!!a && !!ap, "could not build the audio fixture")
            app.ok(MatrixStore.compatible(a, app.gdst) === false,
                   "an audio source is reported compatible with a video destination")
            app.ok(MatrixStore.connect(a, app.gdst) === false,
                   "an audio source was connected to a video destination")
            app.ok(MatrixStore.connect(app.gsrcs[0], ap) === false,
                   "a video source was connected to an audio destination")
            // ... and the audio pair must work
            app.ok(MatrixStore.connect(a, ap) === true, "audio -> audio was refused")
            const e = MatrixStore.connections[a + "|" + ap]
            app.ok(e && e.slot === 0, "an audio connection should use inlet 0")
            break
        }
        case 5: {
            // fan-out: one source into many destinations, then remove the source
            const src = mk("solidcolor")
            const dsts = []
            for (let i = 0; i < 4; ++i) dsts.push(mk("videoprobe"))
            for (const d of dsts)
                app.ok(MatrixStore.connect(src, d) === true, "fan-out connect refused")
            app.ok(MatrixStore.connectionsOf(src).length === 4,
                   "expected 4 outgoing connections")
            NodeStore.remove(src)
            app.ok(MatrixStore.connectionsOf(src).length === 0,
                   "removing the source left its connections behind")
            for (const d of dsts)
                app.ok(MatrixStore.usedSlots(d).length === 0,
                       "a destination still reports a used slot after the source went")
            break
        }
        case 6: {
            // a reconfigure rebuilds the device; the cables are hub-to-hub and
            // must survive it
            const src = mk("solidcolor")
            const d = mk("shmdataout")
            app.ok(MatrixStore.connect(src, d) === true, "could not connect to shmdataout")
            const r = NodeCatalog.recipe("shmdataout")
            const p2 = defaultsOf(r); p2.path = "/tmp/scenic_reconf_test"
            app.ok(NodeStore.reconfigure(d, r.makeSettings(p2), p2) === true,
                   "reconfigure reported failure")
            app.ok(MatrixStore.isConnected(src, d),
                   "the connection did not survive a reconfigure")
            app.ok(NodeStore.creationInfo[d].settings.Path === "/tmp/scenic_reconf_test",
                   "the new settings were not recorded")
            break
        }
        default:
            graphTimer.stop()
            app.finish()
        }
    }
}
