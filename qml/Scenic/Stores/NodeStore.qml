pragma Singleton
import QtQuick
import Scenic

// Registry of the matrix's sources (rows) and destinations (columns).
//
// A node is an optional score device plus a few processes on the root
// interval, all named after the node id:
//
//   video source       <id>_dev -> <id>_crop -> <id>_geo -> <id>_hub
//   video destination  <id>_hub (8-input mixer) -> <id>_fx -> <id>_dev
//   audio              <id>_hub (gain), bound to <id>_dev or an audio address
//   process recipes    <id>_proc, cabled into or out of the hub
//
// The hub is what MatrixStore cables and what thumbnails read. Data bridges
// are sockets rather than engine objects; BridgeStore owns them.
//
// Engine objects are never cached: they are looked up by name, and the row
// models are rebuilt from the hubs that exist in the document. Undo and redo
// recreate objects under the same names, so refresh() is all it takes to
// follow them.
QtObject {
    id: root

    property ListModel sources: ListModel {}
    property ListModel destinations: ListModel {}
    property int counter: 0

    // node shown in the inspector ("" = none)
    property string selectedNodeId: ""

    // nodeId -> { kind, label, role, mediaType, hasDevice, settings, params }.
    // Entries outlive their node so that undoing a removal can bring it back;
    // whether a node is live is decided by exists().
    property var creationInfo: ({})
    // node ids in creation order, which is the matrix order
    property var nodeOrder: []

    // device-tree values of a restored session, applied once the engine runs
    property var pendingDeviceParams: []

    signal nodesChanged()

    // Undo/redo handler for the state score does not hold: a bridge's socket
    // and a node's creationInfo. The payload is { nodeId, info }; a null info
    // closes the bridge. Serialized in backups, so the name must not change.
    readonly property string infoCommand: "scenic.node.info"

    Component.onCompleted: Score.registerCommandHandler(
        infoCommand, p => root.applyInfo(p.nodeId, p.info ?? null))

    // Removing or rebuilding a device while the engine runs is not supported
    // by score, so those edits run between stop and play. Nested calls stop
    // once. It is a pass-through while a session loads (the load brackets
    // itself) and when playback is not wanted, e.g. in the headless tests.
    // Creating a device is safe while running and is not bracketed.
    property bool playbackDesired: false
    property int _playSuspendDepth: 0

    function withPlaybackStopped(fn) {
        const bracket = _playSuspendDepth === 0 && playbackDesired
                        && !SessionStore.restoring
        if (bracket)
            Score.stop()
        _playSuspendDepth += 1
        try {
            fn()
        } finally {
            _playSuspendDepth -= 1
            if (bracket && playbackDesired)
                Score.play()
        }
    }

    // --- lookup --------------------------------------------------------------
    function shaderPath(file) {
        return Util.urlToLocalFile(Qt.resolvedUrl("../shaders/" + file))
    }

    function hubName(nodeId) { return nodeId + "_hub" }
    function hub(nodeId) { return Score.find(nodeId + "_hub") }
    function crop(nodeId) { return Score.find(nodeId + "_crop") }
    function geo(nodeId) { return Score.find(nodeId + "_geo") }
    //! The process whose controls the inspector shows: the colour stage of a
    //! video destination, otherwise the hub itself.
    function fx(nodeId) { return Score.find(nodeId + "_fx") ?? hub(nodeId) }

    function exists(nodeId) {
        return hub(nodeId) !== null || BridgeStore.isBridge(nodeId)
    }

    function get(nodeId) {
        for (const model of [sources, destinations])
            for (let i = 0; i < model.count; ++i)
                if (model.get(i).nodeId === nodeId)
                    return model.get(i)
        return null
    }

    //! Rebuild the row models from creationInfo and the document. A model is
    //! only reset when its rows actually changed, so thumbnails are not torn
    //! down on every edit.
    function refresh() {
        const srcRows = [], dstRows = []
        for (const id of nodeOrder) {
            const info = creationInfo[id]
            if (!info || !exists(id))
                continue
            const recipe = NodeCatalog.recipe(info.kind)
            ;(info.role === "source" ? srcRows : dstRows).push({
                nodeId: id, label: info.label, kind: info.kind,
                typeLabel: recipe ? recipe.label : info.kind,
                mediaType: info.mediaType, role: info.role
            })
        }
        syncModel(sources, srcRows)
        syncModel(destinations, dstRows)
        if (selectedNodeId !== "" && !exists(selectedNodeId))
            selectedNodeId = ""
        nodesChanged()
    }

    function syncModel(model: ListModel, rows: var) {
        let same = model.count === rows.length
        for (let i = 0; same && i < rows.length; ++i)
            same = model.get(i).nodeId === rows[i].nodeId
                && model.get(i).label === rows[i].label
        if (same)
            return
        model.clear()
        for (const r of rows)
            model.append(r)
    }

    //! Whether a device's settings hold credentials: the TURN password, in
    //! the pipelines of the WebRTC nodes.
    function holdsCredentials() {
        if (SettingsStore.turnPassword === "")
            return false
        for (const id of nodeOrder) {
            const info = creationInfo[id]
            const recipe = info ? NodeCatalog.recipe(info.kind) : null
            if (recipe && recipe.derivedSettings && exists(id))
                return true
        }
        return false
    }

    // --- creation ------------------------------------------------------------
    function create(recipe, settings, label, fixedId, params) {
        const id = applyCreate(recipe, settings, label, fixedId, params)
        if (id)
            HistoryStore.push("create " + id)
        return id
    }

    //! Create a node without recording a history label. A fixed id is used by
    //! session restore; otherwise a fresh one is allocated.
    function applyCreate(recipe, settings, label, fixedId, params) {
        let nodeId = fixedId
        if (!nodeId) {
            counter += 1
            nodeId = (recipe.role === "source" ? "src_" : "dst_")
                     + recipe.kind + "_" + counter
        }
        const bridge = recipe.transport !== ""
        const info = {
            kind: recipe.kind, label: label ?? recipe.label,
            role: recipe.role, mediaType: recipe.mediaType,
            hasDevice: recipe.protocol !== "",
            settings: bridge ? null : (settings ?? recipe.settings ?? null),
            params: params ?? null
        }

        if (bridge) {
            // Open it first: a port that cannot be bound must not leave a
            // command behind. The command then only records the node.
            if (!BridgeStore.open(nodeId, recipe, info.params ?? {}, info.label))
                return null
            Score.pushCommand(infoCommand, { nodeId, info: null }, { nodeId, info })
        } else {
            let ok = false
            Score.withMacro(() => { ok = buildNode(nodeId, recipe, info) })
            if (!ok)
                return null
        }

        let ci = creationInfo
        ci[nodeId] = info
        creationInfo = ci
        if (nodeOrder.indexOf(nodeId) === -1) {
            let o = nodeOrder
            o.push(nodeId)
            nodeOrder = o
        }
        refresh()
        SessionStore.markDirty()
        return nodeId
    }

    //! Create the device and process chain of a node. Runs inside a macro.
    function buildNode(nodeId, recipe, info) {
        const devName = nodeId + "_dev"
        if (info.hasDevice) {
            Score.createDevice(devName, recipe.protocol, info.settings)
            // createDevice does not report failure: look for the result. A node
            // without its device would route to nothing, so it is not created
            // (e.g. NDI without the NDI runtime).
            if (!Score.device(devName)) {
                console.error("NodeStore: device creation failed for", devName)
                NotificationStore.error(
                    Translations.t("Could not create the device for ") + info.label)
                return false
            }
        }

        const itv = Score.rootInterval()
        const named = (proc, suffix) => {
            if (proc)
                Score.setName(proc, nodeId + suffix)
            return proc
        }
        const isf = file => Score.createProcess(itv, Uuids.isf, shaderPath(file))
        const cable = (from, to, what) => {
            if (!from || !to || !Score.createCable(from, to))
                console.error("NodeStore: could not cable", what, "for", nodeId)
        }

        let hubProc = null
        if (recipe.mediaType === "video" && recipe.role === "source") {
            const cropProc = named(isf("crop.fs"), "_crop")
            const geoProc = named(isf("transform.fs"), "_geo")
            hubProc = named(isf("colorcontrols.fs"), "_hub")
            if (cropProc && geoProc && hubProc) {
                // crop.fs defaults to a half-size window; start from the full frame
                for (const k of ["width", "height"]) {
                    const port = Score.port(cropProc, k)
                    if (port)
                        Score.setValue(port, 1.0)
                }
                cable(Score.outlet(cropProc, 0), Score.port(geoProc, "inputImage"),
                      "crop -> transform")
                cable(Score.outlet(geoProc, 0), Score.port(hubProc, "inputImage"),
                      "transform -> colour")
            }
        } else if (recipe.mediaType === "video") {
            hubProc = named(isf("mixer8.fs"), "_hub")
            const fxProc = named(isf("colorcontrols.fs"), "_fx")
            if (hubProc && fxProc)
                cable(Score.outlet(hubProc, 0), Score.port(fxProc, "inputImage"),
                      "mixer -> colour")
        } else {
            hubProc = named(Score.createProcess(itv, Uuids.gain, ""), "_hub")
            // the Gain control defaults to 0, which would silence every route
            const g = hubProc ? Score.port(hubProc, "Gain") : null
            if (g)
                Score.setValue(g, 1)
        }

        if (!hubProc) {
            console.error("NodeStore: hub creation failed for", nodeId)
            if (info.hasDevice)
                Score.removeDevice(devName)
            return false
        }

        if (recipe.process !== "")
            buildProcess(nodeId, recipe, info.params)
        bindDevice(nodeId, recipe)
        return true
    }

    //! The <id>_proc of a process recipe (video file, LTC), cabled to the hub.
    function buildProcess(nodeId: string, recipe: var, params: var) {
        const data = recipe.makeProcessData ? recipe.makeProcessData(params ?? {})
                                            : recipe.processData
        const proc = Score.createProcess(Score.rootInterval(), recipe.process, data)
        if (!proc) {
            console.error("NodeStore: process creation failed:", recipe.process)
            return
        }
        Score.setName(proc, nodeId + "_proc")
        const ok = recipe.role === "source"
                 ? Score.createCable(Score.outlet(proc, 0), headInlet(nodeId, recipe.mediaType))
                 : Score.createCable(tailOutlet(nodeId), Score.inlet(proc, 0))
        if (!ok)
            console.error("NodeStore: could not cable the process of", nodeId)
    }

    //! Where a source's media enters its chain.
    function headInlet(nodeId, mediaType) {
        const h = hub(nodeId)
        if (!h)
            return null
        return mediaType === "video" ? Score.port(crop(nodeId) ?? h, "inputImage")
                                     : Score.inlet(h, 0)
    }

    //! Where a destination's media leaves its chain.
    function tailOutlet(nodeId) {
        const f = fx(nodeId)
        return f ? Score.outlet(f, 0) : null
    }

    //! Bind the head (source) or tail (destination) of a node's chain to the
    //! address given by its recipe.
    function bindDevice(nodeId: string, recipe: var) {
        const addr = recipe.addr ? recipe.addr(nodeId + "_dev") : ""
        if (!addr)
            return
        if (recipe.role === "source") {
            const inlet = headInlet(nodeId, recipe.mediaType)
            if (inlet)
                Score.setAddress(inlet, addr)
            return
        }
        const port = tailOutlet(nodeId)
        if (!port)
            return
        Score.setAddress(port, addr)
        // An outlet only writes to its address when it is not cabled, and avnd
        // audio outlets are implicitly cabled to the parent interval: without
        // this the sound goes to the master output instead of the device.
        if (recipe.mediaType === "audio")
            Score.setPropagate(port, false)
    }

    // --- reconfiguration -----------------------------------------------------
    //! Apply new settings and params to a node: rebuild its device, its
    //! process, or reopen its socket. Undoable, connections are kept.
    function reconfigure(nodeId, newSettings, newParams) {
        const info = creationInfo[nodeId]
        const recipe = info ? NodeCatalog.recipe(info.kind) : null
        if (!recipe || !exists(nodeId))
            return false
        const next = Object.assign({}, info, {
            settings: info.hasDevice ? newSettings : info.settings,
            params: newParams ?? info.params
        })

        const edit = () => Score.withMacro(() => {
            if (info.hasDevice) {
                const devName = nodeId + "_dev"
                Score.removeDevice(devName)
                Score.createDevice(devName, recipe.protocol, next.settings)
                bindDevice(nodeId, recipe)
            } else if (recipe.process !== "") {
                const old = Score.find(nodeId + "_proc")
                if (old)
                    Score.remove(old)
                buildProcess(nodeId, recipe, next.params)
            }
            // records the new info, and reopens a bridge with it
            Score.pushCommand(infoCommand, { nodeId, info }, { nodeId, info: next })
        })
        if (info.hasDevice)
            withPlaybackStopped(edit)
        else
            edit()

        HistoryStore.push("reconfigure " + nodeId)
        SessionStore.markDirty()
        return true
    }

    //! Handler of infoCommand, run by undo and redo.
    function applyInfo(nodeId: string, info: var) {
        if (info) {
            let ci = creationInfo
            ci[nodeId] = info
            creationInfo = ci
            const recipe = NodeCatalog.recipe(info.kind)
            if (recipe && recipe.transport !== ""
                    && !BridgeStore.isOpenWith(nodeId, info.params ?? {}))
                BridgeStore.open(nodeId, recipe, info.params ?? {}, info.label)
        } else {
            BridgeStore.close(nodeId)
        }
        refresh()
        MatrixStore.refresh()
    }

    // --- removal -------------------------------------------------------------
    function remove(nodeId) {
        if (!exists(nodeId))
            return
        applyRemove(nodeId)
        HistoryStore.push("remove " + nodeId)
    }

    //! Remove a node, its connections and its entries in every scene, as one
    //! undoable command.
    function applyRemove(nodeId) {
        if (!exists(nodeId))
            return
        if (selectedNodeId === nodeId)
            selectedNodeId = ""
        const info = creationInfo[nodeId]
        const hasDevice = !!(info && info.hasDevice)

        const edit = () => Score.withMacro(() => {
            SceneStore.forgetNode(nodeId)
            MatrixStore.removeCablesOf(nodeId)
            if (BridgeStore.isBridge(nodeId)) {
                Score.pushCommand(infoCommand, { nodeId, info }, { nodeId, info: null })
                return
            }
            for (const suffix of ["_proc", "_crop", "_geo", "_fx", "_hub"]) {
                const p = Score.find(nodeId + suffix)
                if (p)
                    Score.remove(p)
            }
            if (hasDevice)
                Score.removeDevice(nodeId + "_dev")
        })
        if (hasDevice)
            withPlaybackStopped(edit)
        else
            edit()

        refresh()
        MatrixStore.refresh()
        SessionStore.markDirty()
    }

    function clear() {
        withPlaybackStopped(() => {
            for (const id of nodeOrder.slice())
                if (exists(id))
                    applyRemove(id)
        })
        creationInfo = ({})
        nodeOrder = []
        counter = 0
        MatrixStore.forgetAll()
        refresh()
    }

    // --- sessions ------------------------------------------------------------
    //! A device-tree value in a form Device.write accepts: vectors read back
    //! as {x, y[, z[, w]]} objects but must be written as arrays.
    function asWritableValue(v) {
        if (v !== null && typeof v === "object" && !Array.isArray(v)
                && v.x !== undefined && v.y !== undefined) {
            if (v.w !== undefined) return [v.x, v.y, v.z, v.w]
            if (v.z !== undefined) return [v.x, v.y, v.z]
            return [v.x, v.y]
        }
        return v
    }

    function readDeviceParams(nodeId: string, recipe: var): var {
        const out = {}
        let any = false
        for (const dp of (recipe ? recipe.deviceParams : [])) {
            const v = Device.read(nodeId + "_dev:" + dp.addr)
            if (v !== undefined && v !== null) {
                out[dp.addr] = asWritableValue(v)
                any = true
            }
        }
        return any ? out : null
    }

    function writeDeviceParams(nodeId: string, values: var) {
        for (const addr in values ?? {})
            Device.write(nodeId + "_dev:" + addr, asWritableValue(values[addr]))
    }

    function flushDeviceParams() {
        const q = pendingDeviceParams
        pendingDeviceParams = []
        for (const e of q)
            writeDeviceParams(e.id, e.values)
    }

    function serialize() {
        const nodes = []
        for (const model of [sources, destinations]) {
            for (let i = 0; i < model.count; ++i) {
                const id = model.get(i).nodeId
                const info = creationInfo[id]
                const r = NodeCatalog.recipe(info.kind)
                // Enumerated devices are created from settings that are opaque
                // to JS; the engine's own description of the device is what
                // makes them restorable.
                const enumerated = !!(r && r.enumerate)
                // derived settings can hold credentials, and are made again
                const derived = !!(r && r.derivedSettings)
                const preset = proc => proc ? Score.savePreset(proc) : null
                nodes.push({
                    nodeId: id, kind: info.kind, label: info.label,
                    enumerated: enumerated,
                    deviceSettings: info.hasDevice && !derived
                                    ? (Score.deviceSettings(id + "_dev") ?? null) : null,
                    settings: enumerated || derived ? null : info.settings,
                    params: info.params,
                    deviceParams: readDeviceParams(id, r),
                    preset: preset(fx(id)),
                    cropPreset: preset(crop(id)),
                    geoPreset: preset(geo(id))
                })
            }
        }
        return { counter, nodes }
    }

    function restore(data) {
        clear()
        // Ids of restored nodes are fixed; start counting above all of them.
        let maxId = 0
        for (const n of data.nodes ?? []) {
            const m = /_(\d+)$/.exec(n.nodeId ?? "")
            if (m)
                maxId = Math.max(maxId, Number(m[1]))
        }
        counter = Math.max(data.counter ?? 0, maxId)

        for (const n of data.nodes ?? []) {
            const r = NodeCatalog.recipe(n.kind)
            if (!r) {
                console.error("NodeStore: unknown kind", n.kind)
                continue
            }
            if (n.nodeId && exists(n.nodeId)) {
                console.error("NodeStore: session has a duplicate node id", n.nodeId)
                continue
            }
            // Recipe settings are authoritative; enumerated devices, which have
            // none, are rebuilt from the engine's description, and derived
            // settings from the params and the current app settings.
            const settings = r.derivedSettings && n.params
                           ? r.makeSettings(n.params)
                           : n.settings ?? (r.enumerate ? n.deviceSettings : undefined)
            if (!settings && r.enumerate) {
                NotificationStore.error(
                    Translations.t("Re-select this device, its settings could not be saved: ")
                    + (n.label ?? n.kind))
                continue
            }
            applyCreate(r, settings, n.label, n.nodeId, n.params)
            const presets = [[fx(n.nodeId), n.preset],
                             [crop(n.nodeId), n.cropPreset],
                             [geo(n.nodeId), n.geoPreset]]
            let loaded = false
            for (const [proc, preset] of presets) {
                if (proc && preset) {
                    Score.loadPreset(proc, preset)
                    loaded = true
                }
            }
            // loadPreset rebuilds the ports and drops their address binding
            if (loaded)
                bindDevice(n.nodeId, r)
            // A new device applies its defaults as it starts, overwriting
            // anything written now: apply these once the engine runs again.
            if (n.deviceParams)
                pendingDeviceParams = pendingDeviceParams.concat(
                    [{ id: n.nodeId, values: n.deviceParams }])
        }
    }
}
