pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic
import Scenic

// Page navigation: the logo, then one entry per page.
Rectangle {
    id: rail
    width: 108
    color: Style.surface

    // 0 = Matrix, 1 = Settings, 2 = Help
    property int currentIndex: 0

    Column {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: 0

        // Logo
        Item {
            width: parent.width
            height: 132
            Image {
                anchors.centerIn: parent
                width: 60
                fillMode: Image.PreserveAspectFit
                source: Qt.resolvedUrl("../assets/Scenic.svg")
                smooth: true
            }
        }

        Repeater {
            model: [
                { label: Translations.t("Matrix"),   glyph: "⤡" },
                { label: Translations.t("Settings"), glyph: "⚙" },
                { label: Translations.t("Help"),     glyph: "ⓘ" }
            ]
            delegate: ItemDelegate {
                id: entry
                required property int index
                required property var modelData
                width: rail.width
                height: 52
                readonly property bool active: rail.currentIndex === index

                background: Rectangle {
                    color: entry.active ? Style.itemSelected
                         : entry.hovered ? Style.surfaceHovered : "transparent"
                    Rectangle {   // active accent bar
                        width: 3; height: parent.height
                        color: Style.accent
                        visible: entry.active
                    }
                }

                contentItem: Row {
                    spacing: 10
                    leftPadding: 14
                    Label {
                        text: entry.modelData.glyph
                        color: entry.active ? Style.accent : Style.textDim
                        font.pixelSize: 18
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Label {
                        text: entry.modelData.label
                        color: entry.active ? Style.text : Style.textDim
                        font.pixelSize: Style.fontSize
                        font.capitalization: Font.AllUppercase
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                onClicked: rail.currentIndex = entry.index
            }
        }
    }
}
