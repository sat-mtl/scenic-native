import QtQuick
import Scenic

// Open one camera, then remove the node, announcing each phase. The driver
// (tools/test-camera-leak.sh) watches the process's open /dev/video* handles
// across the phases: score must not still hold the camera after the node is
// gone.
//
// With no camera it reports NOCAM and the driver skips.
Item {
    id: root
    property var shell
    property string nodeId: ""

    function say(m) {
        console.log("[leak]", m)
        const p = Util.environmentVariable("SCENIC_LEAK_LOG")
        if (p !== "")
            Util.writeFile(p, Util.readFile(p) + m + "\n")
    }

    function pickMode() {
        for (const g of root.shell.cameraGroups) {
            if (String(g.title).indexOf("Default") === 0)
                continue
            if (g.items.length < 1)
                continue
            return { group: g.title, mode: g.items[0] }
        }
        return null
    }

    property int step: 0

    Timer {
        interval: 3000
        repeat: true
        running: true
        onTriggered: {
            root.step++
            try {
                if (root.step === 1) {
                    const p = root.pickMode()
                    if (!p) { root.say("NOCAM"); Qt.exit(0); return }
                    root.say("open " + p.mode.name)
                    root.nodeId = NodeStore.create(
                        NodeCatalog.recipe("camera"), p.mode.settings, p.group) ?? ""
                    if (root.nodeId === "") { root.say("OPEN FAILED"); Qt.exit(1); return }
                    const wid = NodeStore.create(NodeCatalog.recipe("window"))
                    MatrixStore.connect(root.nodeId, wid)
                    root.say("OPENED")
                } else if (root.step === 2) {
                    root.say("remove " + root.nodeId)
                    NodeStore.remove(root.nodeId)
                    root.nodeId = ""
                    root.say("REMOVED")
                } else if (root.step === 4) {
                    root.say("DONE")
                    Qt.exit(0)
                }
            } catch (e) {
                root.say("EXCEPTION " + e)
                Qt.exit(1)
            }
        }
    }
}
