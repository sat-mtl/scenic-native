import QtQuick
import QtQuick.Controls.Basic
import Scenic

// The Basic style paints the checked track in palette.dark, which is the
// inspector's own background: neither the track nor the state would be visible.
Switch {
    id: control

    padding: 2

    indicator: Rectangle {
        implicitWidth: 40
        implicitHeight: 20
        x: control.leftPadding
        y: control.topPadding + (control.availableHeight - height) / 2
        radius: height / 2
        color: control.checked ? Style.connected : Style.item
        border.width: 1
        border.color: control.checked ? Style.connected
                    : control.hovered ? Style.itemHovered : Style.surfaceSelected

        Rectangle {
            x: 2 + control.visualPosition * (parent.width - width - 4)
            y: 2
            width: parent.height - 4
            height: width
            radius: width / 2
            color: control.checked ? Style.accentText : Style.text

            Behavior on x {
                enabled: !control.down
                NumberAnimation { duration: 100 }
            }
        }
    }
}
