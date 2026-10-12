import QtQuick
import QtQuick.Controls.Basic
import Scenic

// The Basic style sizes a spinbox at 140px of field plus two 40px indicators,
// which does not fit two of them side by side in the inspector.
SpinBox {
    id: control

    padding: 2
    font.pixelSize: Style.fontSizeSmall

    background: Rectangle {
        implicitWidth: 92
        implicitHeight: 26
        color: Style.background
        border.width: 1
        border.color: control.activeFocus ? Style.accent : Style.item
    }

    contentItem: TextInput {
        z: 2
        text: control.displayText
        clip: width < implicitWidth
        font: control.font
        color: Style.text
        selectionColor: Style.accent
        selectedTextColor: Style.accentText
        horizontalAlignment: Qt.AlignHCenter
        verticalAlignment: Qt.AlignVCenter
        readOnly: !control.editable
        validator: control.validator
        inputMethodHints: control.inputMethodHints
    }

    up.indicator: Rectangle {
        x: control.width - width
        height: control.height
        implicitWidth: 22
        color: control.up.pressed ? Style.itemHovered
             : control.up.hovered ? Style.itemSelected : Style.item
        Label {
            anchors.centerIn: parent
            text: "+"
            color: Style.text
            font.pixelSize: Style.fontSize
        }
    }

    down.indicator: Rectangle {
        height: control.height
        implicitWidth: 22
        color: control.down.pressed ? Style.itemHovered
             : control.down.hovered ? Style.itemSelected : Style.item
        Label {
            anchors.centerIn: parent
            text: "−"
            color: Style.text
            font.pixelSize: Style.fontSize
        }
    }
}
