import QtQuick
import QtQuick.Controls.Basic
import Scenic

// A toolbar button that opens a menu (+ Sources, + Destinations).
Button {
    id: btn
    flat: true
    implicitHeight: 34

    contentItem: Label {
        text: btn.text
        color: btn.hovered ? Style.text : Style.textDim
        font.pixelSize: Style.fontSize
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        leftPadding: 12
        rightPadding: 12
    }
    background: Rectangle {
        radius: Style.radius
        color: btn.down ? Style.itemSelected
             : btn.hovered ? Style.itemHovered : Style.item
    }
}
