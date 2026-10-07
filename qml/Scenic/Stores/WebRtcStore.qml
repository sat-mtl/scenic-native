pragma Singleton
import QtQuick
import Scenic

// Client of the gst-webrtc-signalling protocol, as spoken by
// gst-webrtc-signalling-server, Scenic 5, aiguille and gstwebrtc-api:
//   welcome {peerId}                          server -> client
//   setPeerStatus {roles: ["listener"], meta} client -> server
//   list, answered by list {producers}        client -> server -> client
//   peerStatusChanged {peerId, roles, meta}   server -> client
// Remote producers can be subscribed to as matrix sources; publishing adds a
// webrtcsink destination (Nodes/WebrtcPub*.qml).
//
// The socket is libossia's WebSocket client, which ships with score: it
// reaches ws://host:port, without a path, query or TLS. The WebRTC nodes
// themselves connect with GStreamer, which takes any signalling URI.
QtObject {
    id: root

    property bool connected: false
    property string peerId: ""
    property ListModel producers: ListModel {}
    property var sock: null

    property Timer refreshTimer: Timer {
        interval: 5000
        repeat: true
        running: root.connected
        onTriggered: root.send({ type: "list" })
    }

    //! { host, port } of a ws:// URI, or null for one this client cannot reach.
    function endpoint(uri) {
        const m = /^ws:\/\/([^\/:?#]+|\[[^\]]+\])(?::(\d+))?\/?$/.exec(String(uri).trim())
        return m ? { host: m[1].replace(/^\[|\]$/g, ""), port: m[2] ?? "80" } : null
    }

    function connect() {
        disconnect()
        const ep = endpoint(SettingsStore.signallerUri)
        if (!ep) {
            NotificationStore.error(Translations.t("Signalling: ")
                + Translations.t("the peer list needs a ws://host:port address"))
            return
        }
        sock = Protocols.outboundWS({
            Transport: { Host: ep.host, Port: ep.port },
            onOpen: () => {
                root.connected = true
                NotificationStore.info(Translations.t("Connected") + " — "
                                       + SettingsStore.signallerUri)
            },
            onClose: () => root.closed(),
            onError: () => {
                NotificationStore.error(Translations.t("Signalling: ")
                    + Translations.t("cannot reach ") + SettingsStore.signallerUri)
                root.closed()
            },
            onTextMessage: msg => root.handle(msg)
        })
    }

    function disconnect() {
        if (sock)
            sock.close()
        closed()
    }

    function closed() {
        sock = null
        connected = false
        peerId = ""
        producers.clear()
    }

    function send(obj) {
        if (sock && connected)
            sock.write(JSON.stringify(obj))
    }

    function handle(text) {
        if (Util.environmentVariable("SCENIC_WS_DEBUG") === "1")
            console.log("[ws<]", text)
        let msg
        try { msg = JSON.parse(text) } catch (e) { return }
        switch (msg.type) {
        case "welcome":
            peerId = msg.peerId
            send({ type: "setPeerStatus",
                   roles: ["listener"],
                   meta: { peer_name: SettingsStore.peerName } })
            send({ type: "list" })
            break
        case "list": {
            // updated in place: this arrives every few seconds, and a reset
            // would recreate every delegate under the user's pointer
            const seen = ({})
            for (const p of msg.producers ?? []) {
                seen[p.id] = true
                upsertProducer(p.id, p.meta)
            }
            for (let i = producers.count - 1; i >= 0; --i)
                if (!seen[producers.get(i).producerId])
                    producers.remove(i)
            break
        }
        case "peerStatusChanged": {
            const roles = msg.roles ?? []
            if (roles.indexOf("producer") !== -1)
                upsertProducer(msg.peerId, msg.meta)
            else
                removeProducer(msg.peerId)
            break
        }
        default:
            break
        }
    }

    function upsertProducer(id, meta) {
        meta = meta ?? {}
        for (let i = 0; i < producers.count; ++i) {
            if (producers.get(i).producerId === id) {
                producers.setProperty(i, "name", meta.name ?? "")
                producers.setProperty(i, "peerName", meta.peer_name ?? "")
                producers.setProperty(i, "mediaType", meta.media_type ?? "video")
                return
            }
        }
        producers.append({
            producerId: id,
            name: meta.name ?? "",
            peerName: meta.peer_name ?? "",
            mediaType: meta.media_type ?? "video"
        })
    }

    function removeProducer(id) {
        for (let i = 0; i < producers.count; ++i)
            if (producers.get(i).producerId === id) { producers.remove(i); return }
    }

    function subscribe(producerId, name, peerName, mediaType) {
        const kind = mediaType === "audio" ? "webrtcsub_audio" : "webrtcsub_video"
        const recipe = NodeCatalog.recipe(kind)
        const params = { uri: SettingsStore.signallerUri, producerId: producerId }
        const label = (peerName !== "" ? peerName + " / " : "") + (name !== "" ? name : "webrtc")
        return NodeStore.create(recipe, recipe.makeSettings(params), label,
                                undefined, params)
    }

    function publish(mediaType, streamName) {
        const kind = mediaType === "audio" ? "webrtcpub_audio" : "webrtcpub_video"
        const recipe = NodeCatalog.recipe(kind)
        const params = { uri: SettingsStore.signallerUri,
                         name: streamName ?? (mediaType + "0"),
                         peer: SettingsStore.peerName.replace(/[\s"]/g, "_") }
        const label = Translations.t("Publish") + " " + params.name
        return NodeStore.create(recipe, recipe.makeSettings(params), label,
                                undefined, params)
    }
}
