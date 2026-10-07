pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Scenic

// Visual review of every creation dialog: renders each recipe's fields inline
// (respecting visibleWhen) so the layouts can be screenshotted. Not shipped.
ApplicationWindow {
    id: w
    visible: true
    width: 980
    height: 900
    color: Style.background

    FontLoader { source: Qt.resolvedUrl("../qml/Scenic/assets/fonts/Inter-Regular.ttf") }
    FontLoader { source: Qt.resolvedUrl("../qml/Scenic/assets/fonts/Inter-Medium.ttf") }
    FontLoader { source: Qt.resolvedUrl("../qml/Scenic/assets/fonts/Inter-Bold.ttf") }

    // recipes that open a dialog, plus a couple of windowcapture modes
    function withFields(list) {
        return list.filter(r => r.fields && !r.hidden)
    }
    readonly property var entries: {
        const src = withFields(NodeCatalog.sources)
        const dst = withFields(NodeCatalog.destinations)
        const all = []
        for (const r of src.concat(dst)) {
            if (r.kind === "windowcapture") {
                all.push({ recipe: r, mode: 0, tag: " (A Window)" })
                all.push({ recipe: r, mode: 3, tag: " (Region)" })
            } else {
                all.push({ recipe: r, mode: 1, tag: "" })
            }
        }
        return all
    }

    Flickable {
        id: flick
        anchors.fill: parent
        anchors.margins: 12
        contentHeight: grid.height
        Grid {
            id: grid
            columns: 3
            columnSpacing: 12
            rowSpacing: 12
            Repeater {
                model: w.entries
                delegate: Rectangle {
                    id: card
                    required property var modelData
                    width: 300
                    height: col.height + 24
                    color: Style.surface
                    border.color: Style.item

                    property var vals: {
                        const v = {}
                        for (const f of card.modelData.recipe.fields)
                            v[f.key] = f.def
                        v.mode = card.modelData.mode
                        return v
                    }

                    ColumnLayout {
                        id: col
                        x: 12; y: 12
                        width: parent.width - 24
                        spacing: 8
                        Label {
                            text: card.modelData.recipe.label + card.modelData.tag
                            color: Style.text
                            font.pixelSize: Style.fontSize
                            font.bold: true
                        }
                        Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Style.item }
                        Repeater {
                            model: card.modelData.recipe.fields
                            delegate: FieldEditor {
                                required property var modelData
                                Layout.fillWidth: true
                                visible: !modelData.visibleWhen || modelData.visibleWhen(card.vals)
                                field: modelData.type ? modelData
                                     : Object.assign({}, modelData,
                                             { type: modelData.file ? "file" : "string" })
                                value: card.vals[modelData.key] ?? modelData.def
                            }
                        }
                    }
                }
            }
        }
    }

    Timer {
        interval: 1500; running: Util.environmentVariable("SHOT") !== ""
        onTriggered: flick.grabToImage(function(r) {
            r.saveToFile(Util.environmentVariable("SHOT"))
            console.log("[gallery] saved"); Qt.exit(0)
        })
    }
}
