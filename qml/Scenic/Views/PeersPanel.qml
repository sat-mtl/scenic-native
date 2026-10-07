pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Scenic

// Telepresence: the signalling connection, publication of local streams, and
// the remote streams, which become matrix sources when subscribed to.
Drawer {
    id: panel

    edge: Qt.LeftEdge
    width: 340
    height: parent ? parent.height : 0
    modal: false
    interactive: false

    background: Rectangle { color: Style.surface }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Style.spacing
        spacing: Style.spacing

        RowLayout {
            Layout.fillWidth: true
            Label {
                Layout.fillWidth: true
                text: Translations.t("Peers")
                color: Style.accent
                font.pixelSize: Style.fontSizeLarge
                font.bold: true
            }
            ToolButton { text: "✕"; onClicked: panel.close() }
        }

        RowLayout {
            Layout.fillWidth: true
            Rectangle {
                Layout.preferredWidth: 10
                Layout.preferredHeight: 10
                radius: 5
                color: WebRtcStore.connected ? Style.connected : Style.item
            }
            Label {
                Layout.fillWidth: true
                text: WebRtcStore.connected
                      ? Translations.t("Connected") : Translations.t("Not connected")
                color: Style.textDim
                font.pixelSize: Style.fontSizeSmall
            }
            Button {
                text: WebRtcStore.connected ? Translations.t("Disconnect") : Translations.t("Connect")
                onClicked: WebRtcStore.connected
                           ? WebRtcStore.disconnect() : WebRtcStore.connect()
            }
        }

        Label {
            text: Translations.t("Publish")
            color: Style.text
            font.bold: true
        }
        RowLayout {
            Button {
                text: Translations.t("Video")
                enabled: WebRtcStore.connected
                onClicked: WebRtcStore.publish("video")
            }
            Button {
                text: Translations.t("Audio")
                enabled: WebRtcStore.connected
                onClicked: WebRtcStore.publish("audio")
            }
        }

        Label {
            text: Translations.t("Subscribe")
            color: Style.text
            font.bold: true
        }

        ListView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 4
            model: WebRtcStore.producers

            delegate: Rectangle {
                id: row
                required property var model
                width: ListView.view.width
                height: 48
                radius: Style.radius
                color: Style.item
                border.color: Style.itemSelected

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 6
                    spacing: Style.spacing

                    Label {
                        text: row.model.mediaType === "audio" ? "♫" : "▣"
                        color: Style.accent
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        Label {
                            Layout.fillWidth: true
                            text: row.model.name !== "" ? row.model.name : row.model.producerId
                            color: Style.text
                            font.pixelSize: Style.fontSizeSmall
                            elide: Text.ElideRight
                        }
                        Label {
                            Layout.fillWidth: true
                            text: row.model.peerName
                            color: Style.textDim
                            font.pixelSize: Style.fontSizeSmall
                            elide: Text.ElideRight
                        }
                    }
                    Button {
                        text: "+"
                        onClicked: WebRtcStore.subscribe(
                            row.model.producerId, row.model.name,
                            row.model.peerName, row.model.mediaType)
                    }
                }
            }
        }
    }
}
