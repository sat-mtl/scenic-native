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
        enumerator.enumerate = false
        enumerator.enumerate = true
    }

    property QtObject enumerator: UI.DeviceEnumerator {
        deviceType: root.deviceType
        enumerate: true
    }

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
