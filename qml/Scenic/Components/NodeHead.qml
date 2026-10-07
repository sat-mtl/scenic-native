import QtQuick
import QtQuick.Controls.Basic
import Score.UI as UI
import Scenic

// Head of a source row: name and type, and a live thumbnail for video.
Rectangle {
    id: head

    property string nodeId
    property string label
    property string typeLabel
    property string mediaType

    signal previewRequested(string nodeId)

    readonly property bool selected: NodeStore.selectedNodeId === nodeId
    readonly property bool isVideo: mediaType === "video"
    readonly property bool showThumb: isVideo && SettingsStore.thumbnailsEnabled

    color: selected ? Style.itemSelected
         : headMouse.containsMouse ? Style.surfaceHovered : Style.item

    MouseArea {
        id: headMouse
        anchors.fill: parent
        hoverEnabled: true
        onClicked: NodeStore.selectedNodeId =
            (NodeStore.selectedNodeId === head.nodeId ? "" : head.nodeId)
    }

    Row {
        anchors.fill: parent
        anchors.margins: 6
        spacing: 6

        Column {
            width: parent.width - media.width - parent.spacing
            anchors.verticalCenter: parent.verticalCenter
            spacing: 1

            Row {
                width: parent.width
                spacing: 2
                Label {
                    width: parent.width - buttons.width
                    text: head.label
                    color: head.selected ? Style.text : Style.textDim
                    font.pixelSize: Style.fontSizeSmall
                    font.bold: true
                    elide: Text.ElideRight
                    verticalAlignment: Text.AlignVCenter
                    ToolTip.text: head.label
                    ToolTip.visible: labelHover.hovered && head.label.length > 18
                    HoverHandler { id: labelHover }
                }
                Row {
                    id: buttons
                    spacing: 0
                    ToolButton {
                        width: 20; height: 20
                        text: "⤢"
                        font.pixelSize: 11
                        visible: head.isVideo
                        ToolTip.text: Translations.t("Preview"); ToolTip.visible: hovered
                        onClicked: head.previewRequested(head.nodeId)
                    }
                    ToolButton {
                        width: 20; height: 20
                        text: "✕"
                        font.pixelSize: 10
                        ToolTip.text: Translations.t("Remove"); ToolTip.visible: hovered
                        onClicked: NodeStore.remove(head.nodeId)
                    }
                }
            }

            Label {
                width: parent.width
                text: head.typeLabel
                color: Style.textDisabled
                font.pixelSize: Style.fontSizeSmall
                elide: Text.ElideRight
            }
        }

        Item {
            id: media
            width: head.height * 16 / 9 * 0.55
            height: parent.height
            anchors.verticalCenter: parent.verticalCenter

            Rectangle {
                id: thumbFrame
                anchors.centerIn: parent
                width: parent.width
                height: width * 9 / 16
                color: "black"
                visible: head.showThumb
                Loader {
                    anchors.fill: thumbFrame
                    active: thumbFrame.visible
                    sourceComponent: UI.TextureSource {
                        process: NodeStore.hubName(head.nodeId)
                        port: 0
                    }
                }
            }
            Label {
                anchors.centerIn: parent
                visible: !head.isVideo
                text: "🔊"
                font.pixelSize: 18
                color: Style.textDim
            }
        }
    }
}
