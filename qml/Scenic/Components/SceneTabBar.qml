pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic
import Scenic

Rectangle {
    id: bar
    height: 32
    color: Style.surface

    Row {
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        anchors.leftMargin: Style.spacing
        spacing: 4

        Repeater {
            model: SceneStore.scenes
            delegate: Rectangle {
                id: tab
                required property var model
                readonly property bool active: SceneStore.activeSceneId === model.sceneId
                width: tabLabel.implicitWidth + 40
                height: 26
                color: active ? Style.itemSelected
                     : Style.item

                Label {
                    id: tabLabel
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: 8
                    text: tab.model.name
                    color: tab.active ? Style.text : Style.textDim
                    font.pixelSize: Style.fontSizeSmall
                    font.bold: tab.active
                }

                ToolButton {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: 20; height: 20
                    text: "✕"
                    font.pixelSize: 9
                    visible: SceneStore.scenes.count > 1
                    onClicked: SceneStore.removeScene(tab.model.sceneId)
                }

                Rectangle {
                    anchors.bottom: parent.bottom
                    width: parent.width
                    height: 2
                    color: Style.accent
                    visible: tab.active
                }

                TapHandler {
                    onTapped: SceneStore.activate(tab.model.sceneId)
                    onDoubleTapped: {
                        renameField.sceneId = tab.model.sceneId
                        renameField.text = tab.model.name
                        renameField.visible = true
                        renameField.forceActiveFocus()
                    }
                }
            }
        }

        ToolButton {
            width: 26; height: 26
            text: "+"
            onClicked: SceneStore.addScene()
        }
    }

    TextField {
        id: renameField
        property string sceneId: ""
        visible: false
        anchors.verticalCenter: parent.verticalCenter
        anchors.right: parent.right
        anchors.rightMargin: Style.spacing
        width: 160
        onAccepted: {
            if (text.length > 0)
                SceneStore.renameScene(sceneId, text)
            visible = false
        }
        onActiveFocusChanged: if (!activeFocus) visible = false
    }
}
