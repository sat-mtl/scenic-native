pragma Singleton
import QtQuick
import Scenic

// The data plane: UDP / TCP / WebSocket / serial / MIDI bridges and the links
// between them.
//
// Bridges are sockets from libossia's qml_protocols (the `Protocols` global of
// score's script engine), not engine objects: they have no ports and no place
// in the execution graph, so a link is not a score cable. Links are kept here
// and made undoable through Score.pushCommand.
//
// Every message goes through one pivot form, which is what lets any input
// feed any output:
//
//     { address: string|null, values: array|null, bytes: ArrayBuffer|null }
//
// A decoder fills in what its codec knows; an encoder uses what it needs and
// derives the rest (see midiToOsc / oscToMidi).
QtObject {
    id: root

    // nodeId -> { sock, dec, transport, codec, params }
    property var channels: ({})
    // "src|dst" -> true
    property var links: ({})

    // Undo/redo handler of a link, payload { src, dst, linked }. Serialized in
    // backups, so the name must not change.
    readonly property string linkCommand: "scenic.bridge.link"

    Component.onCompleted: Score.registerCommandHandler(
        linkCommand, p => root.applyLink(p.src, p.dst, !!p.linked))

    function key(srcId, dstId) { return srcId + "|" + dstId }
    function isLinked(srcId, dstId) { return key(srcId, dstId) in links }
    function isBridge(nodeId) { return nodeId in channels }

    //! True if the bridge is open with these parameters. Key order does not
    //! matter: parameters coming back from a command have their keys sorted.
    function isOpenWith(nodeId, params) {
        const c = channels[nodeId]
        if (!c)
            return false
        const a = Object.keys(c.params), b = Object.keys(params ?? {})
        return a.length === b.length
            && a.every(k => JSON.stringify(c.params[k]) === JSON.stringify(params[k]))
    }

    // --- bytes ---------------------------------------------------------------
    function toBytes(buf: var): var {
        return buf ? new Uint8Array(buf) : new Uint8Array(0)
    }

    function fromBytes(arr: var): var {
        const b = new Uint8Array(arr.length)
        for (let i = 0; i < arr.length; ++i)
            b[i] = arr[i] & 0xFF
        return b.buffer
    }

    // --- MIDI <-> OSC --------------------------------------------------------
    // The usual mapping, /midi/<channel>/<what>[/<n>] <value>, in both
    // directions: a message converted one way and back comes out unchanged.
    function midiToOsc(bytes: var): var {
        if (bytes.length === 0)
            return { address: "/midi/raw", values: [] }
        const status = bytes[0] & 0xF0
        const ch = (bytes[0] & 0x0F) + 1
        const d1 = bytes.length > 1 ? bytes[1] : 0
        const d2 = bytes.length > 2 ? bytes[2] : 0
        const at = what => "/midi/" + ch + "/" + what
        switch (status) {
        case 0x90: return { address: at("note/" + d1), values: [d2] }
        case 0x80: return { address: at("note/" + d1), values: [0] }
        case 0xA0: return { address: at("aftertouch/" + d1), values: [d2] }
        case 0xB0: return { address: at("cc/" + d1), values: [d2] }
        case 0xC0: return { address: at("program"), values: [d1] }
        case 0xD0: return { address: at("pressure"), values: [d1] }
        case 0xE0: return { address: at("bend"), values: [d1 | (d2 << 7)] }
        default:   return { address: "/midi/raw", values: Array.from(bytes) }
        }
    }

    //! The MIDI bytes for an OSC message, or null if it has no MIDI meaning.
    function oscToMidi(address: string, values: var): var {
        const v = values ?? []
        const parts = String(address ?? "").split("/").filter(s => s.length > 0)
        if (parts[0] !== "midi")
            return null
        if (parts.length === 2 && parts[1] === "raw")
            return v.length > 0 ? v.map(x => Number(x) & 0xFF) : null
        if (parts.length < 3)
            return null
        const ch = (Math.max(1, Math.min(16, Number(parts[1]) || 1)) - 1) & 0x0F
        const n = parts.length > 3 ? (Number(parts[3]) & 0x7F) : 0
        const a = Number(v[0]) || 0
        switch (parts[2]) {
        case "note":       return [(a > 0 ? 0x90 : 0x80) | ch, n, a & 0x7F]
        case "cc":         return [0xB0 | ch, n, a & 0x7F]
        case "aftertouch": return [0xA0 | ch, n, a & 0x7F]
        case "program":    return [0xC0 | ch, a & 0x7F]
        case "pressure":   return [0xD0 | ch, a & 0x7F]
        case "bend":       return [0xE0 | ch, a & 0x7F, (a >> 7) & 0x7F]
        }
        return null
    }

    // --- sockets -------------------------------------------------------------
    //! A MIDI port by name, or the first one when no name is given.
    function midiPort(name: string, outbound: bool): var {
        const list = outbound ? Protocols.outboundMIDIDevices()
                              : Protocols.inboundMIDIDevices()
        if (!list || list.length === 0)
            return null
        if (!name)
            return list[0]
        for (const port of list)
            if (port.Name === name || port.DisplayName === name)
                return port
        return null
    }

    function openSocket(recipe, p, codec, onMessage, onError) {
        const inbound = recipe.role === "source"
        const port = String(p.port ?? 9000)
        const listen = { Bind: p.bind ?? "0.0.0.0", Port: port }
        const connect = { Host: p.host ?? "127.0.0.1", Port: port }
        // OSC over a byte stream needs packet boundaries: SLIP, as in OSC 1.1
        const framing = codec === "osc" ? { type: "slip" } : undefined

        switch (recipe.transport) {
        case "udp":
            return inbound
                ? Protocols.inboundUDP({ Transport: listen, onMessage, onError })
                : Protocols.outboundUDP({ Transport: connect, onError })
        case "tcp":
            // a TCP or WebSocket server delivers per client connection
            return inbound
                ? Protocols.inboundTCP({ Transport: listen, Framing: framing, onError,
                                         onConnection: conn => conn.receive(onMessage) })
                : Protocols.outboundTCP({ Transport: connect, Framing: framing, onError })
        case "ws":
            return inbound
                ? Protocols.inboundWS({ Transport: listen, onError,
                                        onConnection: conn => { conn.onBytes = onMessage } })
                : Protocols.outboundWS({ Transport: connect, onError })
        case "serial":
            return Protocols.serial({
                Transport: { Port: p.device ?? "", BaudRate: Number(p.baud ?? 115200) },
                Framing: framing, onError,
                onMessage: inbound ? onMessage : undefined })
        case "midi": {
            const midi = midiPort(p.device ?? "", !inbound)
            if (!midi)
                throw new Error(Translations.t("no MIDI port: ") + (p.device ?? ""))
            return inbound
                ? Protocols.inboundMIDI({ Transport: midi, onMessage, onError })
                : Protocols.outboundMIDI({ Transport: midi, onError })
        }
        }
        return null
    }

    //! Open a bridge, or reopen it with new parameters. Its links are kept.
    function open(nodeId, recipe, params, label) {
        const p = params ?? {}
        const codec = p.codec ?? recipe.defaultCodec
        const name = label ?? recipe.label
        const onError = e => {
            console.warn("BridgeStore:", nodeId, e)
            NotificationStore.error(name + ": " + e)
        }
        const onMessage = buf => root.inbound(nodeId, buf)

        closeSocket(nodeId)
        let sock = null, why = ""
        try {
            sock = openSocket(recipe, p, codec, onMessage, onError)
        } catch (e) {
            why = " (" + (e.message ?? e) + ")"
        }
        if (!sock) {
            NotificationStore.error(Translations.t("Could not open ") + name + why)
            return false
        }
        const dec = (codec === "osc" && recipe.role === "source")
            ? Protocols.osc({ onOsc: (address, values) =>
                  root.deliver(nodeId, { address, values, bytes: null }) })
            : null

        let c = channels
        c[nodeId] = { sock, dec, transport: recipe.transport, codec, params: p }
        channels = c
        return true
    }

    function closeSocket(nodeId) {
        const c = channels[nodeId]
        if (!c || !c.sock || typeof c.sock.close !== "function")
            return
        try {
            c.sock.close()
        } catch (e) {
            console.error("BridgeStore.close:", nodeId, e)
        }
    }

    //! Close a bridge and drop its links.
    function close(nodeId) {
        if (!isBridge(nodeId))
            return
        closeSocket(nodeId)
        let c = channels
        delete c[nodeId]
        channels = c
        let l = links
        for (const k in l)
            if (k.split("|").indexOf(nodeId) !== -1)
                delete l[k]
        links = l
    }

    // --- links ---------------------------------------------------------------
    //! Handler of linkCommand. An undo can name a bridge that no longer
    //! exists; linking it is then a no-op.
    function applyLink(srcId: string, dstId: string, linked: bool) {
        let l = links
        if (!linked)
            delete l[key(srcId, dstId)]
        else if (isBridge(srcId) && isBridge(dstId))
            l[key(srcId, dstId)] = true
        links = l
        MatrixStore.refresh()
        SessionStore.markDirty()
    }

    //! Link two bridges. Joins the caller's macro if one is open.
    function link(srcId, dstId) {
        if (!isBridge(srcId) || !isBridge(dstId))
            return false
        if (!isLinked(srcId, dstId))
            Score.pushCommand(linkCommand, { src: srcId, dst: dstId, linked: false },
                                           { src: srcId, dst: dstId, linked: true })
        return isLinked(srcId, dstId)
    }

    function unlink(srcId, dstId) {
        if (isLinked(srcId, dstId))
            Score.pushCommand(linkCommand, { src: srcId, dst: dstId, linked: true },
                                           { src: srcId, dst: dstId, linked: false })
    }

    // --- routing -------------------------------------------------------------
    //! A socket received a payload: decode it per the node's codec and route.
    function inbound(nodeId: string, payload: var) {
        const c = channels[nodeId]
        if (!c)
            return
        // MIDI sockets deliver { timestamp, bytes: [int] }, the others a buffer
        const buf = payload && payload.bytes !== undefined ? fromBytes(payload.bytes)
                                                           : payload
        if (c.codec === "osc") {
            if (c.dec)
                c.dec.processMessage(buf)   // calls deliver() per message
        } else if (c.codec === "midi") {
            const m = midiToOsc(toBytes(buf))
            deliver(nodeId, { address: m.address, values: m.values, bytes: buf })
        } else {
            deliver(nodeId, { address: null, values: null, bytes: buf })
        }
    }

    function deliver(srcId: string, msg: var) {
        for (const k in links) {
            const parts = k.split("|")
            if (parts[0] === srcId)
                send(parts[1], msg)
        }
    }

    //! Write bytes to a socket, whose write method depends on its transport.
    function writeBytes(c, bytes) {
        if (c.transport === "midi")
            c.sock.sendMessage(Array.from(toBytes(bytes)))
        else if (c.transport === "ws")
            c.sock.writeBinary(bytes)
        else
            c.sock.write(bytes)
    }

    //! Encode a message the way the destination speaks and send it.
    function send(dstId: string, msg: var) {
        const c = channels[dstId]
        if (!c || !c.sock)
            return
        const hasAddress = msg.address !== null && msg.address !== undefined
        try {
            if (c.codec === "osc") {
                // raw bytes go out as an int array under /raw
                if (hasAddress)
                    c.sock.osc(msg.address, msg.values ?? [])
                else
                    c.sock.osc("/raw", Array.from(toBytes(msg.bytes)))
            } else if (c.codec === "midi") {
                // what has no MIDI meaning is dropped rather than sent as noise
                const raw = hasAddress ? oscToMidi(msg.address, msg.values)
                                       : Array.from(toBytes(msg.bytes))
                if (raw && raw.length > 0)
                    writeBytes(c, fromBytes(raw))
            } else if (msg.bytes) {
                writeBytes(c, msg.bytes)
            } else if (c.transport === "ws") {
                // no OSC encoder on a WebSocket: a JSON text frame
                c.sock.write(JSON.stringify({ address: msg.address,
                                              values: msg.values ?? [] }))
            } else if (c.transport === "midi") {
                // an OSC message with no MIDI meaning: dropped
            } else {
                // the socket encodes the OSC form itself
                c.sock.osc(msg.address, msg.values ?? [])
            }
        } catch (e) {
            console.error("BridgeStore.send:", dstId, e)
        }
    }

    // --- sessions ------------------------------------------------------------
    function serialize() {
        return Object.keys(links).map(k => {
            const parts = k.split("|")
            return { src: parts[0], dst: parts[1] }
        })
    }
}
