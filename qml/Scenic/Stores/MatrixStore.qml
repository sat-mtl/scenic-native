pragma Singleton
import QtQuick
import Scenic

// Connections of the routing matrix.
//
// A media connection is a score cable from outlet 0 of the source hub to an
// inlet of the destination hub: one of the mixer's in1..in8 for video, the
// single summing inlet for audio. The connection set is derived from the
// engine by refresh(), never remembered, since cables are anonymous and undo
// recreates them.
//
// Data connections are links between bridges (see BridgeStore); they are
// merged in so that the matrix is one surface.
QtObject {
    id: root

    // "src|dst" -> { slot }: the mixer inlet 1..8 for video, 0 otherwise
    property var connections: ({})

    readonly property int videoSlots: 8

    function key(srcId, dstId) { return srcId + "|" + dstId }
    function isConnected(srcId, dstId) { return key(srcId, dstId) in connections }

    function compatible(srcId, dstId) {
        const s = NodeStore.get(srcId), d = NodeStore.get(dstId)
        return !!s && !!d && s.mediaType === d.mediaType
    }

    function isData(nodeId) {
        const n = NodeStore.get(nodeId)
        return !!n && n.mediaType === "data"
    }

    function usedSlots(dstId) {
        const used = []
        for (const k in connections)
            if (k.endsWith("|" + dstId))
                used.push(connections[k].slot)
        return used
    }

    function freeSlot(dstId) {
        const used = usedSlots(dstId)
        for (let s = 1; s <= videoSlots; ++s)
            if (used.indexOf(s) === -1)
                return s
        return -1
    }

    function connectionsOf(nodeId) {
        const res = []
        for (const k in connections) {
            const parts = k.split("|")
            if (parts[0] === nodeId || parts[1] === nodeId)
                res.push({ src: parts[0], dst: parts[1] })
        }
        return res
    }

    //! The inlets of a destination hub a source can be cabled to, as
    //! [{ slot, port }].
    function hubInlets(dstHub, video) {
        if (!video)
            return [{ slot: 0, port: Score.inlet(dstHub, 0) }]
        const res = []
        for (let slot = 1; slot <= videoSlots; ++slot)
            res.push({ slot, port: Score.port(dstHub, "in" + slot) })
        return res
    }

    //! Re-derive the connection set from the engine and BridgeStore.
    function refresh() {
        const live = {}
        for (const l of BridgeStore.serialize())
            live[key(l.src, l.dst)] = { slot: 0 }

        const dsts = []
        for (let i = 0; i < NodeStore.destinations.count; ++i) {
            const d = NodeStore.destinations.get(i)
            const h = d.mediaType !== "data" ? NodeStore.hub(d.nodeId) : null
            if (h)
                dsts.push({ nodeId: d.nodeId, mediaType: d.mediaType,
                            inlets: hubInlets(h, d.mediaType === "video") })
        }
        for (let i = 0; i < NodeStore.sources.count; ++i) {
            const s = NodeStore.sources.get(i)
            const h = s.mediaType !== "data" ? NodeStore.hub(s.nodeId) : null
            const outlet = h ? Score.outlet(h, 0) : null
            if (!outlet)
                continue
            for (const d of dsts) {
                if (d.mediaType !== s.mediaType)
                    continue
                for (const inl of d.inlets) {
                    if (inl.port && Score.cable(outlet, inl.port)) {
                        live[key(s.nodeId, d.nodeId)] = { slot: inl.slot }
                        break
                    }
                }
            }
        }
        connections = live
    }

    function toggle(srcId, dstId) {
        if (isConnected(srcId, dstId))
            disconnect(srcId, dstId)
        else
            connect(srcId, dstId)
    }

    function connect(srcId, dstId) {
        let ok = false
        Score.withMacro(() => { ok = applyConnect(srcId, dstId) })
        if (ok)
            HistoryStore.push("connect")
        return ok
    }

    function disconnect(srcId, dstId) {
        if (!isConnected(srcId, dstId))
            return
        Score.withMacro(() => applyDisconnect(srcId, dstId))
        HistoryStore.push("disconnect")
    }

    // The apply* functions do not open a macro: the caller decides what one
    // undo step is (a single cell, or a whole scene switch).
    function applyConnect(srcId, dstId) {
        if (isConnected(srcId, dstId) || !compatible(srcId, dstId))
            return false
        if (isData(srcId)) {
            if (!BridgeStore.link(srcId, dstId))
                return false
        } else {
            const srcHub = NodeStore.hub(srcId), dstHub = NodeStore.hub(dstId)
            if (!srcHub || !dstHub)
                return false
            let inlet = null
            if (NodeStore.get(srcId).mediaType === "video") {
                const slot = freeSlot(dstId)
                if (slot < 0) {
                    NotificationStore.warn(Translations.t("Destination is full"))
                    return false
                }
                inlet = Score.port(dstHub, "in" + slot)
            } else {
                inlet = Score.inlet(dstHub, 0)
            }
            if (!inlet || !Score.createCable(Score.outlet(srcHub, 0), inlet))
                return false
        }
        refresh()
        SessionStore.markDirty()
        return true
    }

    function applyDisconnect(srcId, dstId) {
        if (isData(srcId)) {
            BridgeStore.unlink(srcId, dstId)
        } else {
            const cable = cableFor(srcId, dstId)
            if (cable)
                Score.remove(cable)
        }
        refresh()
        SessionStore.markDirty()
    }

    //! The score cable behind a media connection, or null.
    function cableFor(srcId, dstId) {
        const entry = connections[key(srcId, dstId)]
        const srcHub = NodeStore.hub(srcId), dstHub = NodeStore.hub(dstId)
        if (!entry || !srcHub || !dstHub)
            return null
        const outlet = Score.outlet(srcHub, 0)
        const inlet = entry.slot > 0 ? Score.port(dstHub, "in" + entry.slot)
                                     : Score.inlet(dstHub, 0)
        return (outlet && inlet) ? Score.cable(outlet, inlet) : null
    }

    //! Remove every connection of a node, inside the caller's macro.
    function removeCablesOf(nodeId) {
        for (const c of connectionsOf(nodeId)) {
            if (isData(c.src)) {
                BridgeStore.unlink(c.src, c.dst)
            } else {
                const cable = cableFor(c.src, c.dst)
                if (cable)
                    Score.remove(cable)
            }
        }
    }

    function forgetAll() { connections = ({}) }

    // --- sessions ------------------------------------------------------------
    function serialize() {
        return Object.keys(connections).map(k => {
            const parts = k.split("|")
            return { src: parts[0], dst: parts[1] }
        })
    }

    function restore(conns) {
        for (const c of conns ?? [])
            applyConnect(c.src, c.dst)
    }
}
