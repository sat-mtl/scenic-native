pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic
import Scenic

// One category submenu of + Sources / + Destinations.
//
// `group` is { title, items: [{ recipe, devices, nested }] }. An entry with
// devices (an array, possibly empty) becomes a submenu listing them; `nested`
// means the devices are themselves groups, [{ title, items }], as for cameras
// and their capture modes.
//
// Submenus are created with Instantiator and insertMenu: a Repeater can only
// add items, and a Menu is not an item.
Menu {
    id: root

    required property var group
    signal picked(var recipe)
    signal pickedDevice(var recipe, var dev)

    title: Translations.t(group.title)

    readonly property var deviceEntries: (group.items ?? []).filter(e => !!e.devices)
    readonly property var plainEntries: (group.items ?? []).filter(e => !e.devices)

    Instantiator {
        model: root.deviceEntries
        delegate: Menu {
            id: entryMenu
            required property var modelData
            title: modelData.recipe.label

            Instantiator {
                model: entryMenu.modelData.nested ? entryMenu.modelData.devices : []
                delegate: Menu {
                    id: devGroup
                    required property var modelData
                    title: modelData.title
                    Repeater {
                        model: devGroup.modelData.items
                        MenuItem {
                            required property var modelData
                            text: modelData.name
                            onTriggered: root.pickedDevice(
                                entryMenu.modelData.recipe, modelData)
                        }
                    }
                }
                onObjectAdded: (index, object) => entryMenu.insertMenu(index, object)
                onObjectRemoved: (index, object) => entryMenu.removeMenu(object)
            }

            Repeater {
                model: entryMenu.modelData.nested ? [] : entryMenu.modelData.devices
                MenuItem {
                    required property var modelData
                    text: modelData.name
                    onTriggered: root.pickedDevice(entryMenu.modelData.recipe,
                                                   modelData)
                }
            }

            MenuItem {
                enabled: false
                visible: entryMenu.modelData.devices.length === 0
                text: Translations.t("None found")
            }
        }
        onObjectAdded: (index, object) => root.insertMenu(index, object)
        onObjectRemoved: (index, object) => root.removeMenu(object)
    }

    Repeater {
        model: root.plainEntries
        MenuItem {
            required property var modelData
            text: modelData.recipe.label
            onTriggered: root.picked(modelData.recipe)
        }
    }
}
