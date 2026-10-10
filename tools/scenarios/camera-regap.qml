import QtQuick
import Scenic

// How soon after removing a camera node can the same camera be opened again?
//
// The two close paths have very different latencies, which is what this
// measures. With must_stop set in the parameter's destructor the capture is
// closed by the render thread on the next tick that drains REMOVE_NODE, on the
// order of a frame. Without it, renderedNodesChanged() releases the frames but
// the exchange on must_stop returns false, so the capture is closed only when
// the last shared_ptr to the decoder goes away: ~VideoFrameShare moves it into
// a lambda posted to qApp, and the node itself is not destroyed until the
// nursery's 100 ms QTimer fires on the main thread.
//
// So a short gap should separate the two and a long one should not. SCENIC_GAP
// is the delay between remove and the next open, SCENIC_HOLD how long a node is
// kept before removing it, both in ms.
Item {
    id: root
    property var shell
    property var pick: null
    property string lastId: ""
    property int round: 0
    // An explicit sequence, because alternating modes over three rounds gives
    // "aba" and the third open then repeats the first mode: "the Nth open
    // fails" and "re-opening a mode already used fails" are different claims
    // and that sequence cannot tell them apart. "abb" separates them.
    property string seq: Util.environmentVariable("SCENIC_SEQ") || "aba"
    property int rounds: seq.length
    property int gap: parseInt(Util.environmentVariable("SCENIC_GAP")) || 2000
    property int hold: parseInt(Util.environmentVariable("SCENIC_HOLD")) || 2000

    function say(m) {
        console.log("[regap]", m)
        const p = Util.environmentVariable("SCENIC_REGAP_LOG")
        if (p !== "")
            Util.writeFile(p, Util.readFile(p) + m + "\n")
    }

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

    function modeFor(i) {
        return root.seq.charAt(i) === "b" ? root.pick.b : root.pick.a
    }

    function doOpen() {
        root.round++
        if (root.round > root.rounds) { root.say("DONE"); Qt.exit(0); return }
        const m = root.modeFor(root.round - 1)
        root.say("open " + root.round + " " + m.name)
        root.lastId = NodeStore.create(
            NodeCatalog.recipe("camera"), m.settings, root.pick.group) ?? ""
        if (root.lastId === "") { root.say("OPEN FAILED " + root.round); Qt.exit(1); return }
        const wid = NodeStore.create(NodeCatalog.recipe("window"))
        MatrixStore.connect(root.lastId, wid)
        root.say("opened " + root.round + " " + root.lastId)
        holdTimer.interval = root.hold
        holdTimer.start()
    }

    function doRemove() {
        root.say("remove " + root.round + " " + root.lastId)
        NodeStore.remove(root.lastId)
        root.lastId = ""
        root.say("removed " + root.round)
        gapTimer.interval = root.gap
        gapTimer.start()
    }

    Timer { id: holdTimer; repeat: false; onTriggered: root.doRemove() }
    Timer { id: gapTimer;  repeat: false; onTriggered: root.doOpen() }

    // Setup keeps its own unhurried delay: a short gap must not also mean a
    // short wait for playback to come up, or the first open measures that
    // instead.
    Timer {
        interval: 3000
        repeat: false
        running: true
        onTriggered: {
            try {
                Score.play()
                NodeStore.playbackDesired = true
                root.pick = root.pickModes()
                if (!root.pick) { root.say("NOCAM"); Qt.exit(0); return }
                root.say("cycling " + root.pick.group + " seq=" + root.seq
                         + " gap=" + root.gap + " hold=" + root.hold)
                startTimer.start()
            } catch (e) { root.say("EXCEPTION: " + e); Qt.exit(1) }
        }
    }
    Timer { id: startTimer; interval: 2000; repeat: false; onTriggered: root.doOpen() }
}
