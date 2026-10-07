import QtQuick
import Scenic

// Browser streaming demo (tools/demo-browser.sh): publishes a test pattern
// and a test tone over WebRTC, for demo/browser/index.html to watch.
// SCENIC_SIGNALLER, SCENIC_PEER_NAME, SCENIC_STUN, SCENIC_TURN,
// SCENIC_TURN_USER and SCENIC_TURN_PASSWORD override the saved settings for
// this run only; nothing is written to the settings file.
Item {
    id: root
    property var shell

    Timer {
        interval: 1000
        running: true
        onTriggered: {
            const uri = Util.environmentVariable("SCENIC_SIGNALLER")
            if (uri !== "")
                SettingsStore.signallerUri = uri
            const env = {
                SCENIC_PEER_NAME: "peerName", SCENIC_STUN: "stunServer",
                SCENIC_TURN: "turnServer", SCENIC_TURN_USER: "turnUser",
                SCENIC_TURN_PASSWORD: "turnPassword"
            }
            for (const name in env) {
                const value = Util.environmentVariable(name)
                if (value !== "")
                    SettingsStore[env[name]] = value
            }
            WebRtcStore.connect()

            const video = NodeStore.create(NodeCatalog.recipe("videotest"), undefined,
                                           "Test pattern")
            const tone = NodeStore.create(NodeCatalog.recipe("audiotest"), undefined,
                                          "Test tone")
            const videoOut = WebRtcStore.publish("video", "scenic-video")
            const audioOut = WebRtcStore.publish("audio", "scenic-audio")
            const ok = MatrixStore.connect(video, videoOut)
                    && MatrixStore.connect(tone, audioOut)
            console.log("[demo]", ok ? "READY" : "FAILED", "publishing as",
                        SettingsStore.peerName, "to", SettingsStore.signallerUri)
            if (!ok)
                Qt.exit(1)
        }
    }
}
