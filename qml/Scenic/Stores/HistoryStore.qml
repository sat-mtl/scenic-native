pragma Singleton
import QtQuick
import Scenic

// Undo and redo, on score's own command stack.
//
// The stack is the only authority. What it cannot tell is whether a step
// removes or recreates a device, which must happen with the engine stopped;
// so each edit records a label against the undo index it produced, and a step
// without a label is assumed to touch a device.
QtObject {
    id: root

    // Score.canUndo() does not notify: bindings depend on this counter instead.
    property int revision: 0

    readonly property bool canUndo: (revision, Score.canUndo())
    readonly property bool canRedo: (revision, Score.canRedo())

    // engine undo index -> label of the command that reached it
    property var labels: ({})
    property int lastIndex: 0

    //! Label the edit just committed. A macro that committed nothing moved
    //! no index and records nothing.
    function push(label) {
        const idx = Score.undoIndex()
        if (idx !== lastIndex) {
            let l = labels
            l[idx] = label ?? ""
            labels = l
            lastIndex = idx
        }
        revision++
    }

    function resync() {
        NodeStore.refresh()
        MatrixStore.refresh()
        SceneStore.refresh()
    }

    function labelTouchesDevice(label) {
        if (!label) return true
        const sp = label.indexOf(" ")
        const verb = sp < 0 ? label : label.substring(0, sp)
        if (verb !== "create" && verb !== "remove" && verb !== "reconfigure")
            return false
        const info = NodeStore.creationInfo[label.substring(sp + 1)]
        return !!(info && info.hasDevice)
    }

    function undo() {
        if (!Score.canUndo())
            return
        const label = labels[Score.undoIndex()]
        const step = function() { Score.undo(); resync() }
        if (labelTouchesDevice(label)) NodeStore.withPlaybackStopped(step)
        else step()
        lastIndex = Score.undoIndex()
        revision++
    }

    function redo() {
        if (!Score.canRedo())
            return
        const label = labels[Score.undoIndex() + 1]
        const step = function() { Score.redo(); resync() }
        if (labelTouchesDevice(label)) NodeStore.withPlaybackStopped(step)
        else step()
        lastIndex = Score.undoIndex()
        revision++
    }

    //! Forget all labels, e.g. after a session load: the steps it left on the
    //! stack are then treated as touching devices.
    function clear() {
        labels = ({})
        lastIndex = Score.undoIndex()
        revision++
    }
}
