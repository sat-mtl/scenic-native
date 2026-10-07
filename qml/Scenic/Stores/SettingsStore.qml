pragma Singleton
import QtQuick
import Scenic

// App preferences, persisted in scenic.json in the user's configuration
// folder, and the folders the app writes to.
QtObject {
    id: root

    property string language: "en"
    property bool showThumbnails: true
    // SCENIC_NO_THUMBS=1 turns thumbnails off for this run only
    readonly property bool thumbnailsEnabled:
        showThumbnails && Util.environmentVariable("SCENIC_NO_THUMBS") !== "1"
    property string signallerUri: "ws://127.0.0.1:8443"
    property string peerName: ""
    property string authToken: ""
    // ICE servers of the WebRTC nodes. An empty STUN server keeps GStreamer's
    // default; an empty TURN server means no relay.
    property string stunServer: ""
    property string turnServer: ""           // turn://host:port or turns://host:port
    property string turnUser: ""
    property string turnPassword: ""
    property bool loaded: false

    // Windows has no HOME, and keeps configuration in APPDATA
    readonly property string home:
        Util.environmentVariable("HOME") || Util.environmentVariable("USERPROFILE")
    readonly property string configDir: {
        switch (Qt.platform.os) {
        case "windows":
            return (Util.environmentVariable("APPDATA") || home + "/AppData/Roaming")
                    + "/scenic-native"
        case "osx":
            return home + "/Library/Application Support/scenic-native"
        default:
            return (Util.environmentVariable("XDG_CONFIG_HOME") || home + "/.config")
                    + "/scenic-native"
        }
    }
    // sessions and recordings
    readonly property string documentsDir: home + "/Documents/Scenic"
    readonly property string configPath: configDir + "/scenic.json"

    Component.onCompleted: {
        Util.makeDir(configDir)
        load()
    }

    function load() {
        const text = Score.readFile(configPath)
        if (text && text.length > 0) {
            try {
                const d = JSON.parse(text)
                language = d.language ?? language
                showThumbnails = d.showThumbnails ?? showThumbnails
                signallerUri = d.signallerUri ?? signallerUri
                peerName = d.peerName ?? peerName
                authToken = d.authToken ?? authToken
                stunServer = d.stunServer ?? stunServer
                turnServer = d.turnServer ?? turnServer
                turnUser = d.turnUser ?? turnUser
                turnPassword = d.turnPassword ?? turnPassword
            } catch (e) {
                console.error("SettingsStore: invalid config file")
            }
        }
        if (peerName === "")
            // HOSTNAME is usually not exported; HOST is on some systems
            peerName = Util.environmentVariable("HOST")
                    || Util.environmentVariable("HOSTNAME") || "scenic"
        loaded = true
        Translations.language = language
    }

    function save() {
        Util.writeFile(configPath, JSON.stringify({
            language, showThumbnails, signallerUri, peerName, authToken,
            stunServer, turnServer, turnUser, turnPassword
        }, null, 1))
        Translations.language = language
    }
}
