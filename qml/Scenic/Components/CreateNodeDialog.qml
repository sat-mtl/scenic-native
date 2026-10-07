pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Scenic

// Asks for a node type's fields, then creates the node.
Dialog {
    id: dialog

    property var recipe: null
    property var values: ({})

    title: recipe ? recipe.label : ""
    modal: true
    anchors.centerIn: parent
    padding: Style.spacing * 2
    standardButtons: Dialog.Ok | Dialog.Cancel

    // Visible file fields and required fields must not be empty.
    readonly property bool valid: {
        if (!recipe)
            return false
        for (const f of NodeCatalog.fieldsOf(recipe)) {
            if (f.visibleWhen && !f.visibleWhen(values))
                continue
            const t = f.type ?? "string"
            if (t !== "file" && t !== "savefile" && f.required !== true)
                continue
            const v = values[f.key]
            if (v === undefined || v === null || String(v).trim() === "")
                return false
        }
        return true
    }
    onOpened: {
        const ok = standardButton(Dialog.Ok)
        if (ok) ok.enabled = Qt.binding(() => dialog.valid)
    }

    background: Rectangle {
        color: Style.surface
        border.color: Style.item
        radius: Style.radius
    }
    header: Label {
        text: dialog.title
        color: Style.text
        font.pixelSize: Style.fontSizeLarge
        font.bold: true
        elide: Text.ElideRight
        padding: Style.spacing * 2
        bottomPadding: 0
    }

    function openFor(r) {
        recipe = r
        let v = {}
        for (const f of NodeCatalog.fieldsOf(r))
            v[f.key] = f.def
        values = v
        open()
    }

    onAccepted: {
        if (!recipe)
            return
        const settings = recipe.makeSettings ? recipe.makeSettings(values) : undefined
        NodeStore.create(recipe, settings, undefined, undefined, values)
    }

    function setField(key, v) {
        let m = dialog.values
        m[key] = v
        dialog.values = m
    }

    ColumnLayout {
        spacing: Style.spacing
        implicitWidth: 400

        Loader {
            id: customPanel
            Layout.fillWidth: true
            active: !!(dialog.recipe && dialog.recipe.configPanel)
            sourceComponent: dialog.recipe ? dialog.recipe.configPanel : null
            onLoaded: if (item) item.values = Qt.binding(() => dialog.values)
            Connections {
                target: customPanel.item
                ignoreUnknownSignals: true
                function onEdit(key, value) { dialog.setField(key, value) }
            }
        }

        Repeater {
            model: (dialog.recipe && !dialog.recipe.configPanel) ? NodeCatalog.fieldsOf(dialog.recipe) : []
            delegate: FieldEditor {
                required property var modelData
                Layout.fillWidth: true
                visible: !modelData.visibleWhen || modelData.visibleWhen(dialog.values)
                field: modelData
                value: dialog.values[modelData.key] ?? modelData.def
                onEdited: (v) => dialog.setField(modelData.key, v)
            }
        }
    }
}
