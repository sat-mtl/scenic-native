pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic
import Scenic

Column {
    id: overlay
    spacing: 4
    width: 340

    Repeater {
        model: NotificationStore.model
        delegate: Rectangle {
            id: toast
            required property var model
            width: overlay.width
            height: toastText.implicitHeight + 16
            color: model.level === "error" ? Style.error
                 : model.level === "warn" ? Style.warning
                 : Style.notification
            opacity: 0.95

            Label {
                id: toastText
                anchors.fill: parent
                anchors.margins: 8
                text: toast.model.text
                color: toast.model.level === "error" ? Style.text : Style.notificationText
                wrapMode: Text.WordWrap
                font.pixelSize: Style.fontSizeSmall
            }

            TapHandler {
                onTapped: NotificationStore.dismiss(toast.model.noteId)
            }

            Timer {
                interval: 5000
                running: true
                onTriggered: NotificationStore.dismiss(toast.model.noteId)
            }
        }
    }
}
