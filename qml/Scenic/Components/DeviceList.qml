import QtQuick
import Score.UI as UI

// The devices a score protocol enumerates, as a list bindings can follow.
//
// DeviceEnumerator.devices does not notify, and the enumerator fills it over a
// queued connection, so the list is kept here from deviceAdded/deviceRemoved.
QtObject {
    id: root

    property string deviceType
    // [{ category, name, settings }], in the order they were reported
    property var devices: []

    //! Enumerate again. The enumerator finds nothing when it first runs, before
    //! the document exists, and does not retry on its own.
    function refresh() {
        // No deviceType is score's "every protocol known", and it walks them all
        // in one synchronous pass: on Windows that pass never returns.
        if (root.deviceType === "")
            return
        enumerator.enumerate = false
        enumerator.enumerate = true
    }

    // Built inert. `enumerate: true` here is a constant, and QML assigns
    // constants before bindings, so enumeration would start while deviceType
    // was still empty -- the unfiltered pass that follows deadlocks the engine.
    property QtObject enumerator: UI.DeviceEnumerator {
        deviceType: root.deviceType
    }

    // deviceType is in place by now, so this is the first filtered enumeration.
    Component.onCompleted: root.refresh()

    property Connections connections: Connections {
        target: root.enumerator
        // an enumeration reports every device again: replace, do not append
        function onDeviceAdded(factory, category, name, settings) {
            const list = root.devices.filter(
                d => !(d.name === name && d.category === category))
            list.push({ category: category ?? "", name, settings })
            root.devices = list
        }
        function onDeviceRemoved(factory, name) {
            root.devices = root.devices.filter(d => d.name !== name)
        }
    }
}
