import QtQuick
import Scenic

// Removing a camera node closes the capture on the render thread, not in the
// destructor: ~video_texture_input_parameter() calls unregister_node(), which
// only enqueues REMOVE_NODE on GfxContext::tick_commands. That queue is drained
// by run_commands(), reached from updateGraph(), which runs as part of
// rendering. ~GfxContext drains it too, but only to release disowned nodes --
// it never calls removeNodeAndEdges -- so a REMOVE_NODE still queued when
// rendering stops is never acted on.
//
// This removes the node and stops playback immediately afterwards, so the
// command is in the queue when the ticks stop. The camera has to be released
// anyway; if it is not, the capture outlives both the node and playback, and
// nothing will ever close it.
//
// Every other camera scenario keeps playback running throughout, so none of
// them covers this.
Item {
    id: root
    property var shell
    property var pick: null
    property string lastId: ""
    // 0 means stop in the same turn as the removal, the tightest race. A delay
    // lets a tick get in first, which is the control: that one must release.
    property int stopDelay: parseInt(Util.environmentVariable("SCENIC_STOP_DELAY")) || 0

    function say(m) {
        console.log("[stopped]", m)
        const p = Util.environmentVariable("SCENIC_STOPPED_LOG")
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

    function stopPlayback() {
        root.say("STOPPING")
        NodeStore.playbackDesired = false
        Score.stop()
        root.say("STOPPED")
    }

    Timer {
        interval: 3000
        repeat: false
        running: true
        onTriggered: {
            try {
                Score.play()
                NodeStore.playbackDesired = true
                root.pick = root.pickCamera()
                if (!root.pick) { root.say("NOCAM"); Qt.exit(0); return }
                openTimer.start()
            } catch (e) { root.say("EXCEPTION: " + e); Qt.exit(1) }
        }
    }

    Timer {
        id: openTimer
        interval: 2000
        repeat: false
        onTriggered: {
            try {
                root.say("open " + root.pick.mode.name)
                root.lastId = NodeStore.create(
                    NodeCatalog.recipe("camera"), root.pick.mode.settings,
                    root.pick.group) ?? ""
                if (root.lastId === "") { root.say("OPEN FAILED"); Qt.exit(1); return }
                const wid = NodeStore.create(NodeCatalog.recipe("window"))
                MatrixStore.connect(root.lastId, wid)
                root.say("OPENED " + root.lastId)
                holdTimer.start()
            } catch (e) { root.say("EXCEPTION: " + e); Qt.exit(1) }
        }
    }

    Timer {
        id: holdTimer
        interval: 3000
        repeat: false
        onTriggered: {
            try {
                root.say("REMOVING " + root.lastId)
                NodeStore.remove(root.lastId)
                root.lastId = ""
                root.say("REMOVED")
                if (root.stopDelay <= 0) {
                    root.stopPlayback()
                } else {
                    stopTimer.interval = root.stopDelay
                    stopTimer.start()
                }
                doneTimer.start()
            } catch (e) { root.say("EXCEPTION: " + e); Qt.exit(1) }
        }
    }

    Timer { id: stopTimer; repeat: false; onTriggered: root.stopPlayback() }

    // Stay alive well past the stop so the prober can see whether anything
    // releases the device afterwards. Exiting here would close it regardless
    // and hide the leak.
    Timer {
        id: doneTimer
        interval: 12000
        repeat: false
        onTriggered: { root.say("DONE"); Qt.exit(0) }
    }
}
