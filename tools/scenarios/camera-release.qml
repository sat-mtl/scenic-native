import QtQuick
import Scenic

// Does removing a camera node actually close the capture? Measured from
// outside: an external prober tries to open the same camera at each phase, and
// score keeps running throughout, so a probe that fails means score is still
// holding the device.
//
// The two phases before the interesting one are controls. Without them a prober
// that can never open the camera, or one that always can, would look like a
// result:
//   BASELINE  nothing open      -> the probe must succeed
//   OPENED    node holds it     -> the probe must fail
//   REMOVED   node is gone      -> succeeds if the capture was closed, which is
//                                  the claim under test
// A run where BASELINE fails or OPENED succeeds is void, not a verdict.
//
// Phases are held for several ticks so the prober has room to retry, and each
// marker is flushed as it happens.
Item {
    id: root
    property var shell
    property int step: 0
    property string lastId: ""
    property var pick: null

    function say(m) {
        console.log("[release]", m)
        const p = Util.environmentVariable("SCENIC_RELEASE_LOG")
        if (p !== "")
            Util.writeFile(p, Util.readFile(p) + m + "\n")
    }

    function pickCamera() {
        const want = Util.environmentVariable("SCENIC_CYCLE_CAM")
        for (const g of root.shell.cameraGroups) {
            if (String(g.title).indexOf("Default") === 0)
                continue
            if (want !== "" && String(g.title).indexOf(want) < 0)
                continue
            if (g.items.length < 1)
                continue
            return { group: g.title, mode: g.items[0] }
        }
        return null
    }

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
                    root.pick = root.pickCamera()
                    if (!root.pick) { root.say("NOCAM"); Qt.exit(0); return }
                    root.say("BASELINE " + root.pick.group)
                } else if (root.step === 4) {
                    root.say("open " + root.pick.mode.name)
                    root.lastId = NodeStore.create(
                        NodeCatalog.recipe("camera"), root.pick.mode.settings,
                        root.pick.group) ?? ""
                    if (root.lastId === "") { root.say("OPEN FAILED"); Qt.exit(1); return }
                    const wid = NodeStore.create(NodeCatalog.recipe("window"))
                    MatrixStore.connect(root.lastId, wid)
                    root.say("OPENED " + root.lastId)
                } else if (root.step === 8) {
                    root.say("REMOVING " + root.lastId)
                    NodeStore.remove(root.lastId)
                    root.lastId = ""
                    root.say("REMOVED")
                } else if (root.step === 14) {
                    root.say("DONE")
                    Qt.exit(0)
                }
            } catch (e) {
                root.say("EXCEPTION: " + e)
                Qt.exit(1)
            }
        }
    }
}
