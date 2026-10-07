pragma Singleton
import QtQuick
import Scenic

// Named sessions, in the sessions folder of SettingsStore.documentsDir.
//
// A session is <name>.scenic.json: the nodes with their settings and process
// presets, and the scenes. Loading clears the document and replays it through
// the stores. <name>.score, the document itself, is written alongside for
// inspection in score; it is not read back.
QtObject {
    id: root

    property string currentSession: ""
    property bool unsavedChanges: false
    property bool restoring: false

    readonly property string sessionDir: SettingsStore.documentsDir + "/sessions"

    Component.onCompleted: Util.makeDir(sessionDir)

    function path(name) { return sessionDir + "/" + name + ".scenic.json" }
    function scorePath(name) { return sessionDir + "/" + name + ".score" }

    // A session name becomes a file name: keep it to a set that cannot escape
    // sessionDir.
    function validName(name) {
        return typeof name === "string" && name.length > 0 && name.length <= 128
            && /^[A-Za-z0-9 ._-]+$/.test(name)
            && name !== "." && name !== ".."
    }

    function markDirty() {
        if (!restoring)
            unsavedChanges = true
    }

    function list() {
        return Util.listFiles(sessionDir, "*.scenic.json")
            .map(p => p.split("/").pop().replace(".scenic.json", ""))
    }

    function save(name) {
        if (!validName(name)) {
            NotificationStore.error(Translations.t("Invalid session name: ") + name)
            return false
        }
        const data = {
            version: 2,
            application: "scenic-native",
            nodes: NodeStore.serialize(),
            scenes: SceneStore.serialize()
        }
        Util.writeFile(path(name), JSON.stringify(data, null, 1))
        // The document holds every device's settings, credentials included:
        // it is not written while a node uses them, and an existing copy is removed.
        if (NodeStore.holdsCredentials())
            Util.removeFile(scorePath(name))
        else
            Score.saveAs(scorePath(name))
        // Util.writeFile does not report failure
        if (!Util.fileExists(path(name))) {
            NotificationStore.error(Translations.t("Could not write session: ") + name)
            return false
        }
        currentSession = name
        unsavedChanges = false
        NotificationStore.info(Translations.t("Session saved: ") + name)
        return true
    }

    function load(name) {
        if (!validName(name)) {
            NotificationStore.error(Translations.t("Invalid session name: ") + name)
            return false
        }
        const text = Score.readFile(path(name))
        if (!text || text.length === 0) {
            NotificationStore.error(Translations.t("Cannot read session: ") + name)
            return false
        }
        let data
        try { data = JSON.parse(text) } catch (e) {
            NotificationStore.error(Translations.t("Invalid session file: ") + name)
            return false
        }
        // Devices are removed and created: stop the engine for the whole load.
        // `restoring` must be reset even if a malformed file throws.
        restoring = true
        let restored = true
        Score.stop()
        try {
            MatrixStore.forgetAll()
            NodeStore.restore(data.nodes ?? { nodes: [] })
            if (data.version >= 2)
                SceneStore.restore(data.scenes ?? {})
            else {
                SceneStore.clear()
                MatrixStore.restore(data.connections)
            }
        } catch (e) {
            restored = false
            NotificationStore.error(Translations.t("Could not restore session: ") + name)
            console.error("SessionStore.load:", e)
        } finally {
            if (NodeStore.playbackDesired)
                Score.play()
            restoring = false
        }
        Qt.callLater(NodeStore.flushDeviceParams)
        HistoryStore.clear()
        if (!restored)
            return false
        currentSession = name
        unsavedChanges = false
        return true
    }

    function reset() {
        restoring = true
        Score.stop()
        try {
            MatrixStore.forgetAll()
            NodeStore.clear()
            SceneStore.clear()
        } finally {
            if (NodeStore.playbackDesired)
                Score.play()
            restoring = false
        }
        HistoryStore.clear()
        currentSession = ""
        unsavedChanges = false
    }

    function remove(name) {
        if (!validName(name)) {
            NotificationStore.error(Translations.t("Invalid session name: ") + name)
            return
        }
        const okJson = Util.removeFile(path(name))
        const okScore = !Util.fileExists(scorePath(name)) || Util.removeFile(scorePath(name))
        if (!okJson || !okScore)
            NotificationStore.error(Translations.t("Could not delete session: ") + name)
        if (currentSession === name)
            currentSession = ""
    }
}
