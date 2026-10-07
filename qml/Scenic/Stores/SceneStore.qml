pragma Singleton
import QtQuick
import Scenic

// Scenes: named sets of connections. The matrix always shows the active one.
//
// Scene state is stored in the document, as JSON in the root interval's
// comment, so every scene edit is a score command: undo covers it together
// with the cable changes it goes with. Score.setComment joins an open macro,
// which makes a scene switch a single undo step.
//
// The properties below cache that JSON; refresh() re-reads it after undo/redo.
QtObject {
    id: root

    property ListModel scenes: ListModel {}
    property string activeSceneId: ""
    // sceneId -> [{src, dst}]
    property var sceneConnections: ({})
    property int sceneCounter: 0

    // --- document-held state -------------------------------------------
    function readState() {
        const itv = Score.rootInterval()
        if (!itv) return null
        const md = Score.metadata(itv)
        if (!md || !md.comment || md.comment.length === 0) return null
        try {
            const o = JSON.parse(md.comment)
            return (o && o.scenic === 1) ? o : null
        } catch (e) {
            return null   // not ours
        }
    }

    function currentState() {
        const list = []
        for (let i = 0; i < scenes.count; ++i) {
            const s = scenes.get(i)
            list.push({ sceneId: s.sceneId, name: s.name,
                        connections: sceneConnections[s.sceneId] ?? [] })
        }
        return { scenic: 1, active: activeSceneId, counter: sceneCounter, scenes: list }
    }

    function applyState(st) {
        scenes.clear()
        let sc = ({})
        for (const s of st.scenes ?? []) {
            scenes.append({ sceneId: s.sceneId, name: s.name })
            sc[s.sceneId] = s.connections ?? []
        }
        sceneConnections = sc
        sceneCounter = st.counter ?? 0
        activeSceneId = st.active ?? ""
    }

    //! Commit a state object to the document (one command) and refresh the cache.
    function writeState(st) {
        const itv = Score.rootInterval()
        if (itv)
            Score.setComment(itv, JSON.stringify(st))
        applyState(st)
    }

    //! Re-derive the cache from the document. Called after undo/redo.
    function refresh() {
        const st = readState()
        if (st)
            applyState(st)
    }

    // A fresh document has no scene state. Seed the cache without writing it,
    // so that starting the app leaves the undo stack empty.
    function init() {
        const st = readState()
        if (st) { applyState(st); return }
        if (scenes.count === 0) {
            sceneCounter = 1
            const id = "scene_1"
            scenes.append({ sceneId: id, name: Translations.t("Scene 1") })
            let sc = ({}); sc[id] = []; sceneConnections = sc
            activeSceneId = id
        }
    }

    function sceneName(sceneId) {
        for (let i = 0; i < scenes.count; ++i)
            if (scenes.get(i).sceneId === sceneId)
                return scenes.get(i).name
        return ""
    }

    // --- edits (each one a score command) --------------------------------
    function addScene(name) {
        const st = currentState()
        st.counter += 1
        const sceneId = "scene_" + st.counter
        st.scenes.push({ sceneId, name: name ?? (Translations.t("Scene ") + st.counter),
                         connections: [] })
        if (st.active === "")
            st.active = sceneId
        Score.withMacro(function() { writeState(st) })
        HistoryStore.push("scene add " + sceneId)
        SessionStore.markDirty()
        return sceneId
    }

    function removeScene(sceneId) {
        if (scenes.count <= 1)
            return
        const st = currentState()
        st.scenes = st.scenes.filter(s => s.sceneId !== sceneId)
        const wasActive = st.active === sceneId
        Score.withMacro(function() {
            if (wasActive) {
                // switch away first, inside the same command, so the cables of
                // the scene we land on are the ones left in the graph
                const target = st.scenes[0]
                applyDiff(target.connections ?? [])
                st.active = target.sceneId
            }
            writeState(st)
        })
        HistoryStore.push("scene remove " + sceneId)
        SessionStore.markDirty()
    }

    function renameScene(sceneId, name) {
        const st = currentState()
        let found = false
        for (const s of st.scenes)
            if (s.sceneId === sceneId) { s.name = name; found = true }
        if (!found) return
        Score.withMacro(function() { writeState(st) })
        HistoryStore.push("scene rename " + sceneId)
        SessionStore.markDirty()
    }

    //! Snapshot the live cables into the active scene, in the cache only.
    function snapshotActive() {
        if (activeSceneId === "")
            return
        let sc = sceneConnections
        sc[activeSceneId] = MatrixStore.serialize()
        sceneConnections = sc
    }

    function activate(sceneId) {
        if (sceneId === activeSceneId)
            return
        Score.withMacro(function() { applyActivate(sceneId) })
        HistoryStore.push("activate scene " + sceneName(sceneId))
    }

    function applyActivate(sceneId) {
        snapshotActive()
        const st = currentState()
        applyDiff(sceneConnections[sceneId] ?? [])
        st.active = sceneId
        writeState(st)
        SessionStore.markDirty()
    }

    //! Bring the live graph to exactly `target`, without opening a macro.
    function applyDiff(target) {
        const targetKeys = target.map(c => c.src + "|" + c.dst)
        for (const c of MatrixStore.serialize())
            if (targetKeys.indexOf(c.src + "|" + c.dst) === -1)
                MatrixStore.applyDisconnect(c.src, c.dst)
        for (const c of target)
            if (!MatrixStore.isConnected(c.src, c.dst))
                MatrixStore.applyConnect(c.src, c.dst)
    }

    //! Drop a node from every scene. Called inside NodeStore's removal macro.
    function forgetNode(nodeId) {
        const st = currentState()
        for (const s of st.scenes)
            s.connections = (s.connections ?? [])
                .filter(c => c.src !== nodeId && c.dst !== nodeId)
        writeState(st)
    }

    function clear() {
        const st = { scenic: 1, active: "scene_1", counter: 1,
                     scenes: [{ sceneId: "scene_1", name: Translations.t("Scene 1"),
                                connections: [] }] }
        Score.withMacro(function() { writeState(st) })
    }

    // --- sessions ------------------------------------------------------
    function serialize() {
        snapshotActive()
        return currentState()
    }

    function restore(data) {
        const st = { scenic: 1,
                     active: data.active ?? "",
                     counter: data.counter ?? 0,
                     scenes: (data.scenes ?? []).map(s => ({
                         sceneId: s.sceneId, name: s.name,
                         connections: s.connections ?? [] })) }
        if (st.scenes.length === 0) {
            st.counter = 1
            st.scenes = [{ sceneId: "scene_1", name: Translations.t("Scene 1"), connections: [] }]
        }
        const known = st.scenes.map(s => s.sceneId)
        if (known.indexOf(st.active) === -1)
            st.active = known[0]
        Score.withMacro(function() { writeState(st) })
        MatrixStore.restore(sceneConnections[st.active])
    }
}
