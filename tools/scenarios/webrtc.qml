import QtQuick
import Scenic

// Telepresence against a local signalling server and one external producer
// (tools/test-webrtc.sh): subscribe to the producer, publish a test pattern,
// and wait until the publication is listed back by the server.
Item {
    id: root
    property var shell
    property string phase: "connect"
    property int wait: 0
    property bool subscribed: false
    Timer {
        interval: 700
        repeat: true
        running: true
        onTriggered: {
            const L = (m) => console.log("[p3auto]", m)
            const store = WebRtcStore
            switch (root.phase) {
            case "connect":
                store.connect()
                L("connecting to " + SettingsStore.signallerUri)
                root.phase = "await-producer"; root.wait = 0
                break
            case "await-producer":
                if (store.connected && store.producers.count >= 1) {
                    const p = store.producers.get(0)
                    const before = NodeStore.sources.count
                    const nodeId = store.subscribe(p.producerId, p.name,
                                                   p.peerName, p.mediaType)
                    root.subscribed = nodeId !== ""
                                              && NodeStore.sources.count > before
                    L("subscribed " + p.name + " -> node " + nodeId
                      + " (sources " + before + "->" + NodeStore.sources.count + ")")
                    root.phase = "publish"
                } else if (++root.wait > 15) {
                    L("FAIL: no external producer (connected=" + store.connected
                      + " producers=" + store.producers.count + ")")
                    Qt.exit(1)
                }
                break
            case "publish":
                NodeStore.create(NodeCatalog.recipe("videotest"))
                store.publish("video")
                L("created videotest + publish destination")
                root.phase = "route"
                break
            case "route": {
                let src = "", dst = ""
                for (let i = 0; i < NodeStore.sources.count; ++i)
                    if (NodeStore.sources.get(i).kind === "videotest")
                        src = NodeStore.sources.get(i).nodeId
                for (let i = 0; i < NodeStore.destinations.count; ++i)
                    if (NodeStore.destinations.get(i).kind === "webrtcpub_video")
                        dst = NodeStore.destinations.get(i).nodeId
                const ok = src !== "" && dst !== ""
                            ? MatrixStore.connect(src, dst) : false
                L("routed videotest -> publish: " + ok)
                root.phase = "await-own"; root.wait = 0
                break
            }
            case "await-own": {
                let names = []
                for (let i = 0; i < store.producers.count; ++i)
                    names.push(store.producers.get(i).name)
                // Success = external producer subscribed and our own publication
                // is now visible back through the signaller (producers >= 2).
                if (root.subscribed && store.producers.count >= 2) {
                    L("producers=" + JSON.stringify(names)
                      + " subscribe+publish verified — DONE")
                    Qt.exit(0)
                } else if (++root.wait > 15) {
                    L("FAIL: incomplete (subscribed=" + root.subscribed
                      + " producers=" + JSON.stringify(names) + ")")
                    Qt.exit(1)
                }
                break
            }
            }
        }
    }
}
