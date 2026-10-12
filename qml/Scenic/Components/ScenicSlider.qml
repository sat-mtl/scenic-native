import QtQuick
import QtQuick.Controls.Basic
import Scenic

// The Basic style paints the filled part of the groove in palette.dark, which
// is the inspector's own background: the value would be unreadable.
Slider {
    id: control

    background: Rectangle {
        x: control.leftPadding
        y: control.topPadding + (control.availableHeight - height) / 2
        width: control.availableWidth
        height: 4
        radius: 2
        color: Style.item

        Rectangle {
            width: control.position * parent.width
            height: parent.height
            radius: parent.radius
            color: control.enabled ? Style.accent : Style.textDisabled
        }
    }

    handle: Rectangle {
        x: control.leftPadding + control.visualPosition * (control.availableWidth - width)
        y: control.topPadding + (control.availableHeight - height) / 2
        implicitWidth: 14
        implicitHeight: 14
        radius: width / 2
        color: control.pressed ? Style.accent : Style.text
        border.width: 1
        border.color: Style.background
    }
}
