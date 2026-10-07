import QtQuick
import QtQuick.Controls.Basic
import Score.UI as UI
import Scenic

// Full-size preview of a video node's hub texture. Click anywhere to close.
Rectangle {
    id: overlay

    property string nodeId: ""
    visible: nodeId !== ""

    color: Qt.rgba(0, 0, 0, 0.85)

    MouseArea {
        anchors.fill: parent
        onClicked: overlay.nodeId = ""
    }

    UI.TextureSource {
        anchors.fill: overlay
        anchors.margins: 48
        visible: overlay.nodeId !== ""
        process: overlay.nodeId !== "" ? NodeStore.hubName(overlay.nodeId) : ""
        port: 0
    }

    Label {
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.margins: 16
        text: {
            const n = overlay.nodeId !== "" ? NodeStore.get(overlay.nodeId) : null
            return n ? n.label : ""
        }
        color: Style.text
        font.pixelSize: Style.fontSizeLarge
    }
}
