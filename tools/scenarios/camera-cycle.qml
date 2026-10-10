import QtQuick
import Scenic

// Open a camera, remove the node, open a *different* resolution of the same
// camera, twice over. Regression cover for a Windows crash where the capture
// graph outlived the node: the camera stayed busy so the re-open produced no
// frames, and the stale device left a dangling entry in the execution state.
// Execution::findNode calls device_base::get_name() on every registered device,
// and get_name() is non-virtual over a pure virtual get_root_node(), so one
// destroyed entry aborts the process.
//
// Modes are chosen from whatever the machine enumerates, so this runs against
// any camera. With no camera it reports NOCAM and the driver skips.
Item {
    id: root
    property var shell
    property int step: 0
    property var modes: []
    property int modeIdx: -1
    property string lastId: ""

    // One line per event, flushed as it happens: a crash has to leave behind
    // the step it died on.
    function say(m) {
        console.log("[cycle]", m)
        const p = Util.environmentVariable("SCENIC_CYCLE_LOG")
        if (p !== "")
            Util.writeFile(p, Util.readFile(p) + m + "\n")
    }

    // The first camera group offering two distinct resolutions. "Default
    // Camera" is skipped: its negotiated format is not deterministic.
    // SCENIC_CYCLE_CAM narrows it to a group whose title contains that text,
    // which two runs need in order to be comparable: enumeration order is not
    // stable, so "the first group" can be a different camera each time.
    function pickModes() {
        const want = Util.environmentVariable("SCENIC_CYCLE_CAM")
        for (const g of root.shell.cameraGroups) {
            if (String(g.title).indexOf("Default") === 0)
                continue
            if (want !== "" && String(g.title).indexOf(want) < 0)
                continue
            if (g.items.length < 2)
                continue
            return { group: g.title, a: g.items[0], b: g.items[1] }
        }
        return null
    }

    function openMode(m) {
        say("open " + m.name)
        root.lastId = NodeStore.create(
            NodeCatalog.recipe("camera"), m.settings, root.pick.group) ?? ""
        if (root.lastId === "") { say("OPEN FAILED"); return }
        const wid = NodeStore.create(NodeCatalog.recipe("window"))
        MatrixStore.connect(root.lastId, wid)
        say("opened " + root.lastId)
    }

    function closeCurrent() {
        if (root.lastId === "") return
        say("remove " + root.lastId)
        NodeStore.remove(root.lastId)
        root.lastId = ""
    }

    property var pick: null

    Timer {
        interval: 2000
        repeat: true
        running: true
        onTriggered: {
            root.step++
            try {
                if (root.step === 1) {
                    Score.play()
                    NodeStore.playbackDesired = true
                } else if (root.step === 2) {
                    root.pick = root.pickModes()
                    if (!root.pick) { root.say("NOCAM"); Qt.exit(0); return }
                    // The default repeats the first mode, so a failure on the
                    // third open cannot be told apart from a failure to
                    // re-open a mode already used. SCENIC_CYCLE_SEQ ("aba",
                    // "abb", "ab", ...) separates the two.
                    const seq = Util.environmentVariable("SCENIC_CYCLE_SEQ") || "aba"
                    root.modes = []
                    for (const c of seq)
                        root.modes.push(c === "b" ? root.pick.b : root.pick.a)
                    root.say("cycling " + root.pick.group)
                } else if (root.step >= 3) {
                    const phase = (root.step - 3) % 2
                    if (phase === 0) {
                        root.modeIdx++
                        if (root.modeIdx >= root.modes.length) {
                            root.say("DONE")
                            Qt.exit(0)
                            return
                        }
                        root.openMode(root.modes[root.modeIdx])
                    } else {
                        root.closeCurrent()
                    }
                }
            } catch (e) {
                root.say("EXCEPTION: " + e)
                Qt.exit(1)
            }
        }
    }
}
