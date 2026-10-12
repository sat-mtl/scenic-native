import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Scenic

// A labelled editor for one field, its widget chosen by the field's type
// (see NodeType.fields). A change made by the user is emitted by edited();
// while a slider is being dragged, the intermediate values go to editing()
// and the final one to edited(), on release.
RowLayout {
    id: root

    property var field
    property var value
    signal edited(var newValue)
    signal editing(var newValue)

    readonly property string ftype: field.type ?? "string"
    spacing: Style.spacing

    // score names its control inlets in lower case ("bright", "hue"): the
    // inspector capitalises them, leaving an already-capitalised label alone.
    Label {
        text: root.field.label.charAt(0).toUpperCase() + root.field.label.slice(1)
        color: Style.textDim
        font.pixelSize: Style.fontSizeSmall
        Layout.preferredWidth: 96
        Layout.alignment: Qt.AlignVCenter
        wrapMode: Text.WordWrap
    }

    ScenicSwitch {
        visible: root.ftype === "bool"
        checked: root.value === true || root.value === "true"
        onToggled: root.edited(checked)
    }

    ComboBox {
        id: combo
        visible: root.ftype === "enum"
        Layout.fillWidth: true
        textRole: "label"
        valueRole: "value"
        model: root.field.options ?? []
        // a value outside the domain must still show something
        function sync() { currentIndex = Math.max(0, indexOfValue(root.value)) }
        Component.onCompleted: sync()
        Connections {
            target: root
            function onValueChanged() { combo.sync() }
        }
        onActivated: root.edited(currentValue)
    }

    ScenicSpinBox {
        visible: root.ftype === "int"
        Layout.fillWidth: true
        editable: true
        from: root.field.min ?? -2147483647
        to: root.field.max ?? 2147483647
        value: Number(root.value) || 0
        onValueModified: root.edited(value)
    }

    RowLayout {
        visible: root.ftype === "float"
        Layout.fillWidth: true
        spacing: 4
        ScenicSlider {
            id: slider
            Layout.fillWidth: true
            from: root.field.min ?? 0
            to: Math.max(root.field.max ?? 1, from + 1e-6)
            value: Number(root.value) || 0
            // a keyboard step is a whole edit; a drag ends on release
            onMoved: pressed ? root.editing(value) : root.edited(value)
            onPressedChanged: if (!pressed) root.edited(value)
        }
        Label {
            text: slider.value.toFixed(2)
            color: Style.text
            font.pixelSize: Style.fontSizeSmall
            Layout.preferredWidth: 40
            horizontalAlignment: Text.AlignRight
        }
    }

    // two integers, e.g. a position or a size
    RowLayout {
        id: vec
        visible: root.ftype === "vec2"
        Layout.fillWidth: true
        spacing: 4
        // root.value is an array, a list or an {x, y} object (Device.read)
        function component(i) {
            const v = root.value
            if (v === undefined || v === null)
                return 0
            const c = i === 0 ? (v.x ?? v[0]) : (v.y ?? v[1])
            return Number(c) || 0
        }
        ScenicSpinBox {
            id: vx
            Layout.fillWidth: true
            editable: true; from: -32768; to: 32768
            value: vec.component(0)
            onValueModified: root.edited([value, vy.value])
        }
        ScenicSpinBox {
            id: vy
            Layout.fillWidth: true
            editable: true; from: -32768; to: 32768
            value: vec.component(1)
            onValueModified: root.edited([vx.value, value])
        }
    }

    // two to four floats: an ISF position, scale, tiling or colour
    RowLayout {
        id: vecf
        visible: root.ftype === "vecf"
        Layout.fillWidth: true
        spacing: 4

        readonly property int count: root.field.components ?? 2
        readonly property var keys: ["x", "y", "z", "w"]

        function component(i) {
            const v = root.value
            if (v === undefined || v === null)
                return 0
            return Number(Array.isArray(v) ? v[i] : v[keys[i]]) || 0
        }
        function commit(i, nv) {
            const out = []
            for (let k = 0; k < count; ++k)
                out.push(k === i ? nv : component(k))
            root.edited(out)
        }

        Repeater {
            model: vecf.count
            delegate: TextField {
                id: comp
                required property int index
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                font.pixelSize: Style.fontSizeSmall
                padding: 4
                validator: DoubleValidator { notation: DoubleValidator.StandardNotation }
                // assigned, not bound: typing into a bound text breaks the
                // binding for good
                function sync() { text = vecf.component(index).toFixed(3) }
                Component.onCompleted: sync()
                Connections {
                    target: root
                    function onValueChanged() { if (!comp.activeFocus) comp.sync() }
                }
                onEditingFinished: vecf.commit(index, Number(text) || 0)
            }
        }
    }

    TextField {
        id: textField
        visible: root.ftype === "string" || root.ftype === "file" || root.ftype === "savefile"
        Layout.fillWidth: true
        text: root.value !== undefined && root.value !== null ? String(root.value) : ""
        placeholderText: root.field.placeholder ?? ""
        onEditingFinished: if (textField.text !== String(root.value ?? ""))
                               root.edited(textField.text)
    }
    Button {
        visible: root.ftype === "file" || root.ftype === "savefile"
        text: "…"
        implicitWidth: 32
        onClicked: {
            const done = path => {
                if (path && path.length > 0) {
                    textField.text = path
                    root.edited(path)
                }
            }
            if (root.ftype === "savefile")
                Util.saveFileDialog(Translations.t("Save as"), textField.text, "", done)
            else
                Util.openFileDialog(Translations.t("Choose file"), "", "", done)
        }
    }
}
