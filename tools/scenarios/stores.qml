import QtQuick
import Scenic

// The stores end to end: create, connect, scenes, undo/redo, remove, save,
// reset, load, stats, enumeration and translations. Prints "[p1auto] DONE".
Item {
    id: root
    property var shell
    property int step: 0
    property int bad: 0
    property var savedIce: []
    property string pubId: ""
    Timer {
        interval: 1500
        repeat: true
        running: true
        onTriggered: {
            root.step++
            const L = (m) => console.log("[p1auto]", m)
            const A = (cond, m) => { if (!cond) { root.bad++
                                                  console.log("[p1auto] FAIL:", m) } }
            const conns = () => Object.keys(MatrixStore.connections).length
            // an exception in a timer callback is otherwise only logged
            try {
            switch (root.step) {
            case 1:
                // a fresh document must leave the undo stack empty: seeding the
                // default scene must not push a command
                A(!HistoryStore.canUndo, "undo stack not empty at startup")
                NodeStore.create(NodeCatalog.recipe("videotest"))
                NodeStore.create(NodeCatalog.recipe("audiotest"))
                NodeStore.create(NodeCatalog.recipe("window"))
                NodeStore.create(NodeCatalog.recipe("audioout"))
                L("created " + NodeStore.sources.count + "/" + NodeStore.destinations.count)
                A(NodeStore.sources.count === 2, "expected 2 sources")
                A(NodeStore.destinations.count === 2, "expected 2 destinations")
                // audio output has no device of its own and must not be reported
                // as a failed one
                for (let i = 0; i < NotificationStore.model.count; ++i)
                    A(NotificationStore.model.get(i).level !== "error",
                      "creation raised: " + NotificationStore.model.get(i).text)
                break
            case 2:
                MatrixStore.connect("src_videotest_1", "dst_window_3")
                MatrixStore.connect("src_audiotest_2", "dst_audioout_4")
                L("connected " + conns())
                A(conns() === 2, "expected 2 connections, got " + conns())
                {
                    // a slider drag is one undo step, and undo restores the
                    // value from before the drag
                    const fx = NodeStore.fx("src_videotest_1")
                    let port = null
                    for (let i = 0; fx && i < Score.inlets(fx) && !port; ++i)
                        if (Score.valueType(Score.inlet(fx, i)) === "Float")
                            port = Score.inlet(fx, i)
                    A(port !== null, "no float control on the colour stage")
                    if (port) {
                        const before = port.value, idx = Score.undoIndex()
                        for (const v of [0.1, 0.2, 0.3])
                            Score.editValue(port, v)
                        Score.commitEdit()
                        HistoryStore.push("control")
                        A(Score.undoIndex() === idx + 1, "a drag took "
                          + (Score.undoIndex() - idx) + " undo steps, expected 1")
                        A(Math.abs(port.value - 0.3) < 1e-6, "the drag set " + port.value)
                        HistoryStore.undo()
                        A(Math.abs(port.value - before) < 1e-6,
                          "undo left " + port.value + ", expected " + before)
                    }
                }
                break
            case 3: {
                const s2 = SceneStore.addScene("Empty")
                SceneStore.activate(s2)
                const emptyCount = conns()
                SceneStore.activate("scene_1")
                L("scene roundtrip: empty=" + emptyCount + " back=" + conns())
                A(emptyCount === 0, "the new scene should start with no cables")
                A(conns() === 2, "switching back should restore both cables")
                A(SceneStore.scenes.count === 2, "expected 2 scenes")
                break
            }
            case 4:
                HistoryStore.undo()
                L("undo(scene back to Empty): conns=" + conns()
                  + " active=" + SceneStore.activeSceneId)
                A(conns() === 0, "undoing the switch should drop the cables again")
                // undo restores the active scene along with the cables
                A(SceneStore.activeSceneId === "scene_2",
                  "undo left activeSceneId at " + SceneStore.activeSceneId)
                HistoryStore.redo()
                L("redo(scene_1): conns=" + conns()
                  + " active=" + SceneStore.activeSceneId)
                A(conns() === 2, "redo should restore both cables")
                A(SceneStore.activeSceneId === "scene_1",
                  "redo left activeSceneId at " + SceneStore.activeSceneId)
                break
            case 5:
                const before = Score.undoIndex()
                NodeStore.remove("src_videotest_1")
                A(Score.undoIndex() === before + 1, "removing a node took "
                  + (Score.undoIndex() - before) + " undo steps, expected 1")
                L("removed node: sources=" + NodeStore.sources.count + " conns=" + conns())
                A(NodeStore.sources.count === 1, "removal should leave 1 source")
                A(conns() === 1, "removing the source should drop its cable")
                HistoryStore.undo()
                L("undo remove: sources=" + NodeStore.sources.count + " conns=" + conns())
                A(NodeStore.sources.count === 2, "undo should bring the source back")
                A(conns() === 2, "undo should bring its cable back")
                break
            case 6:
                A(SessionStore.save("p2auto") === true, "save() reported failure")
                L("saved; sessions=" + JSON.stringify(SessionStore.list()))
                A(SessionStore.list().indexOf("p2auto") >= 0, "saved session not listed")
                break
            case 7:
                SessionStore.reset()
                L("reset: sources=" + NodeStore.sources.count + " conns=" + conns()
                  + " scenes=" + SceneStore.scenes.count)
                A(NodeStore.sources.count === 0 && NodeStore.destinations.count === 0,
                  "reset left nodes behind")
                A(conns() === 0, "reset left connections behind")
                A(SceneStore.scenes.count === 1, "reset should leave exactly one scene")
                break
            case 8:
                SessionStore.load("p2auto")
                L("loaded: sources=" + NodeStore.sources.count
                  + " dests=" + NodeStore.destinations.count
                  + " conns=" + conns() + " scenes=" + SceneStore.scenes.count
                  + " active=" + SceneStore.activeSceneId)
                A(NodeStore.sources.count === 2, "load lost sources")
                A(NodeStore.destinations.count === 2, "load lost destinations")
                A(conns() === 2, "load lost connections")
                A(SceneStore.scenes.count === 2, "load lost a scene")
                A(SceneStore.activeSceneId === "scene_1", "load restored the wrong scene")
                break
            case 9:
                L("stats: cpu=" + StatsStore.cpuPercent.toFixed(0)
                  + " mem=" + StatsStore.memPercent.toFixed(0)
                  + " iface=" + StatsStore.netInterface)
                A(StatsStore.memPercent > 0, "no memory reading from /proc")
                // score always lists at least a default camera
                L("enumerated: cameras=" + root.shell.devicesFor("camera").length
                  + " ndi=" + root.shell.devicesFor("ndiin").length)
                A(root.shell.devicesFor("camera").length > 0, "the camera enumerator found nothing")
                Translations.language = "fr"
                L("i18n fr Matrix=" + Translations.t("Matrix"))
                A(Translations.t("Matrix") === "Matrice",
                  "fr translation missing for Matrix")
                Translations.language = "en"
                A(Translations.t("Matrix") === "Matrix", "en fallback broken")
                {
                    // fields and enum options can be limited to some platforms
                    const os = Qt.platform.os
                    const f = NodeCatalog.fieldsOf({ fields: [
                        { key: "all" },
                        { key: "here", platforms: [os] },
                        { key: "elsewhere", platforms: ["not-" + os] },
                        { key: "pick", type: "enum", options: [
                            { value: 1 }, { value: 2, platforms: ["not-" + os] }] }
                    ] })
                    A(f.map(x => x.key).join() === "all,here,pick",
                      "fieldsOf kept " + f.map(x => x.key).join())
                    A(f[2].options.length === 1, "fieldsOf kept an option of another platform")
                }
                break
            case 10: {
                // ICE credentials are not saved in a session, and loading it
                // rebuilds the WebRTC pipelines from the current settings
                root.savedIce = [SettingsStore.turnServer, SettingsStore.turnUser,
                                 SettingsStore.turnPassword]
                SettingsStore.turnServer = "turn://127.0.0.1:3478"
                SettingsStore.turnUser = "scenic"
                SettingsStore.turnPassword = "demo/pass:1"
                root.pubId = WebRtcStore.publish("video", "p2turn")
                A(root.pubId, "could not create a WebRTC publication")
                const pipe = (Score.deviceSettings(root.pubId + "_dev") ?? {}).Pipeline ?? ""
                A(pipe.indexOf("turn://scenic:demo%2Fpass%3A1@127.0.0.1:3478") >= 0,
                  "the TURN server is missing or unescaped in: " + pipe)
                A(SessionStore.save("p2turn") === true, "save() reported failure")
                const saved = Score.readFile(SessionStore.path("p2turn")) ?? ""
                A(saved.indexOf("p2turn") >= 0, "the session lost the publication")
                A(saved.indexOf("demo") < 0, "the session file holds the TURN password")
                const doc = Score.readFile(SessionStore.scorePath("p2turn")) ?? ""
                A(doc.indexOf("demo") < 0, "the .score file holds the TURN password")
                break
            }
            case 11: {
                // A step of its own: removing a device in the same event-loop
                // pass that created it crashes score (JS::DeviceContext's
                // queued deviceAdded handler gets a deleted device).
                SettingsStore.turnPassword = "changed"
                SessionStore.load("p2turn")
                const again = (Score.deviceSettings(root.pubId + "_dev") ?? {}).Pipeline ?? ""
                L("restored pipeline has turn-servers: " + (again.indexOf("turn-servers") >= 0))
                A(again.indexOf("scenic:changed@") >= 0,
                  "loading did not rebuild the pipeline from the settings: " + again)
                SessionStore.remove("p2turn")
                ;[SettingsStore.turnServer, SettingsStore.turnUser,
                  SettingsStore.turnPassword] = root.savedIce
                break
            }
            default:
                // leave the session list as it was before the run
                SessionStore.remove("p2auto")
                L("checked with " + root.bad + " problem(s)")
                if (root.bad === 0)
                    L("DONE")
                Qt.exit(root.bad ? 1 : 0)
            }
            } catch (e) {
                root.bad++
                console.log("[p1auto] FAIL: step", root.step, "threw", e)
            }
        }
    }
}
