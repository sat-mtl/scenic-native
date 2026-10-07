pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Scenic

// Inspector of the selected node:
//  - settings: the type's fields; an edit reconfigures the node
//  - device: live device-tree parameters (a monitor's position and size)
//  - controls: the control inlets of the node's processes (crop, transform,
//    colour, gain)
Drawer {
    id: drawer

    edge: Qt.RightEdge
    width: 340
    height: parent ? parent.height : 0
    modal: false
    interactive: false
    visible: NodeStore.selectedNodeId !== ""

    background: Rectangle { color: Style.surface }

    property var recipe: null
    property var params: ({})        // current values of recipe.fields
    property var fields: []
    property var ports: []           // [{ portObj, name, vt, min, max, enums }]

    function rebuild() {
        const id = NodeStore.selectedNodeId
        if (id === "") { recipe = null; fields = []; ports = []; params = {}; return }

        const info = NodeStore.creationInfo[id] ?? {}
        recipe = NodeCatalog.recipe(info.kind)
        fields = NodeCatalog.fieldsOf(recipe)

        let p = {}
        for (const f of fields)
            p[f.key] = (info.params && info.params[f.key] !== undefined)
                     ? info.params[f.key] : f.def
        params = p

        // control inlets of every stage, in signal order
        const list = []
        for (const stage of [NodeStore.crop(id), NodeStore.geo(id), NodeStore.fx(id)]) {
            if (!stage) continue
            const n = Score.inlets(stage)
            for (let i = 0; i < n; ++i) {
                const port = Score.inlet(stage, i)
                if (!port) continue
                const vt = Score.valueType(port)
                if (vt === "") continue
                list.push({
                    portObj: port,
                    name: port.name && port.name.length ? port.name : (vt + " " + i),
                    vt: vt, min: Score.min(port), max: Score.max(port),
                    enums: Score.enumValues(port) ?? []
                })
            }
        }
        ports = list
    }

    function commitField(key, value) {
        const id = NodeStore.selectedNodeId
        if (id === "" || !recipe) return
        let p = params
        p[key] = value
        params = p
        NodeStore.reconfigure(id, recipe.makeSettings ? recipe.makeSettings(p) : null, p)
    }

    Connections {
        target: NodeStore
        function onSelectedNodeIdChanged() { drawer.rebuild() }
        function onNodesChanged() { drawer.rebuild() }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Style.spacing
        spacing: Style.spacing

        // ---- header ----
        RowLayout {
            Layout.fillWidth: true
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                Label {
                    Layout.fillWidth: true
                    text: {
                        const n = NodeStore.get(NodeStore.selectedNodeId)
                        return n ? n.label : ""
                    }
                    color: Style.text
                    font.pixelSize: Style.fontSizeLarge
                    font.bold: true
                    elide: Text.ElideRight
                }
                Label {
                    text: drawer.recipe ? drawer.recipe.label : ""
                    color: Style.textDim
                    font.pixelSize: Style.fontSizeSmall
                }
            }
            ToolButton {
                text: "✕"
                onClicked: NodeStore.selectedNodeId = ""
            }
        }

        Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Style.item }

        Flickable {
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentWidth: width
            contentHeight: content.height
            clip: true
            ScrollBar.vertical: ScrollBar {}

            ColumnLayout {
                id: content
                width: parent.width
                spacing: Style.spacing

                // ---- settings ----
                Label {
                    visible: drawer.fields.length > 0
                             || (drawer.recipe && drawer.recipe.configPanel)
                    text: Translations.t("SETTINGS")
                    color: Style.textDim
                    font.pixelSize: Style.fontSizeSmall
                    font.bold: true
                    font.letterSpacing: 1
                }
                Loader {
                    id: inspPanel
                    Layout.fillWidth: true
                    active: !!(drawer.recipe && drawer.recipe.configPanel)
                    sourceComponent: drawer.recipe ? drawer.recipe.configPanel : null
                    onLoaded: if (item) item.values = Qt.binding(() => drawer.params)
                    Connections {
                        target: inspPanel.item
                        ignoreUnknownSignals: true
                        function onEdit(key, value) { drawer.commitField(key, value) }
                    }
                }
                Repeater {
                    model: (drawer.recipe && drawer.recipe.configPanel) ? [] : drawer.fields
                    delegate: FieldEditor {
                        required property var modelData
                        Layout.fillWidth: true
                        visible: !modelData.visibleWhen
                                 || modelData.visibleWhen(drawer.params)
                        field: modelData
                        value: drawer.params[modelData.key]
                        onEdited: (v) => drawer.commitField(modelData.key, v)
                    }
                }

                // ---- device ----
                Label {
                    visible: drawer.recipe && (drawer.recipe.deviceParams ?? []).length > 0
                    text: Translations.t("DEVICE")
                    color: Style.textDim
                    font.pixelSize: Style.fontSizeSmall
                    font.bold: true
                    font.letterSpacing: 1
                    topPadding: Style.spacing
                }
                Repeater {
                    model: drawer.recipe ? (drawer.recipe.deviceParams ?? []) : []
                    delegate: FieldEditor {
                        required property var modelData
                        readonly property string fullAddr:
                            NodeStore.selectedNodeId + "_dev:" + modelData.addr
                        Layout.fillWidth: true
                        field: modelData
                        value: Device.read(fullAddr)
                        onEdited: (v) => {
                            Device.write(fullAddr, v)
                            SessionStore.markDirty()
                        }
                    }
                }

                // ---- controls ----
                Label {
                    visible: drawer.ports.length > 0
                    text: Translations.t("CONTROLS")
                    color: Style.textDim
                    font.pixelSize: Style.fontSizeSmall
                    font.bold: true
                    font.letterSpacing: 1
                    topPadding: Style.spacing
                }
                Repeater {
                    model: drawer.ports
                    delegate: FieldEditor {
                        required property var modelData
                        Layout.fillWidth: true
                        field: ({
                            label: modelData.name,
                            type: modelData.enums.length > 0 ? "enum"
                                : modelData.vt === "Bool" ? "bool"
                                : modelData.vt === "Int" ? "int"
                                : modelData.vt === "Float" ? "float" : "string",
                            min: modelData.min, max: modelData.max,
                            options: modelData.enums.map(e => ({ value: e, label: String(e) }))
                        })
                        // bound, not copied: a preset can change it after rebuild()
                        value: modelData.vt === "Bool"
                             ? (modelData.portObj.value === true)
                             : modelData.portObj.value
                        // one undo step per gesture, as in score's own controls
                        onEditing: (v) => Score.editValue(modelData.portObj, v)
                        onEdited: (v) => {
                            Score.editValue(modelData.portObj, v)
                            Score.commitEdit()
                            HistoryStore.push("control")
                            SessionStore.markDirty()
                        }
                    }
                }

                Label {
                    visible: drawer.fields.length === 0 && drawer.ports.length === 0
                             && (!drawer.recipe || (drawer.recipe.deviceParams ?? []).length === 0)
                    text: Translations.t("No editable properties")
                    color: Style.textDim
                }
            }
        }

        Button {
            id: delBtn
            Layout.fillWidth: true
            text: Translations.t("Delete")
            onClicked: {
                const id = NodeStore.selectedNodeId
                NodeStore.selectedNodeId = ""
                NodeStore.remove(id)
            }
            contentItem: Label {
                text: delBtn.text
                color: "white"
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
            background: Rectangle {
                radius: Style.radius
                color: delBtn.down ? Qt.darker(Style.error, 1.2)
                     : delBtn.hovered ? Style.error : Qt.darker(Style.error, 1.1)
            }
        }
    }
}
