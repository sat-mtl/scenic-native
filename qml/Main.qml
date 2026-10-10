pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Scenic

ApplicationWindow {
    id: mainWindow
    width: Style.windowWidth
    height: Style.windowHeight
    minimumWidth: Style.windowMinWidth
    minimumHeight: Style.windowMinHeight
    visible: true
    title: "Scenic" + (SessionStore.currentSession !== ""
                       ? " — " + SessionStore.currentSession : "")
           + (SessionStore.unsavedChanges ? " *" : "")
    color: Style.background
    font.family: Style.fontFamily

    palette {
        window: Style.background
        windowText: Style.text
        base: Style.surface
        alternateBase: Style.surfaceSelected
        text: Style.text
        button: Style.item
        buttonText: Style.text
        highlight: Style.accent
        highlightedText: Style.accentText
        placeholderText: Style.textDisabled
        mid: Style.item
        dark: Style.surface
        light: Style.itemHovered
    }

    // the theme's font, bundled so rendering does not depend on the system
    FontLoader { source: Qt.resolvedUrl("Scenic/assets/fonts/Inter-Regular.ttf") }
    FontLoader { source: Qt.resolvedUrl("Scenic/assets/fonts/Inter-Italic.ttf") }
    FontLoader { source: Qt.resolvedUrl("Scenic/assets/fonts/Inter-Medium.ttf") }
    FontLoader { source: Qt.resolvedUrl("Scenic/assets/fonts/Inter-SemiBold.ttf") }
    FontLoader { source: Qt.resolvedUrl("Scenic/assets/fonts/Inter-Bold.ttf") }

    Component.onCompleted: {
        SceneStore.init()
        Score.play()
        NodeStore.playbackDesired = true
        // the first enumeration ran before the document existed
        Qt.callLater(() => {
            for (const list of [cameras, ndi, pipewire, gphoto])
                list.refresh()
        })
        const path = Util.environmentVariable("SCENIC_SCENARIO")
        if (path !== "")
            scenario.setSource(scenarioUrl(path), { shell: mainWindow })
    }

    // ---- enumerated devices ----
    DeviceList { id: cameras; deviceType: Uuids.camera }
    DeviceList { id: ndi; deviceType: Uuids.ndiIn }
    DeviceList { id: pipewire; deviceType: Uuids.pipewireIn }
    DeviceList { id: gphoto; deviceType: Uuids.gphoto2 }

    // The camera enumerator reports one entry per capture mode, with the camera
    // in `category`: group them per camera, in the order reported.
    readonly property var cameraGroups: {
        const groups = {}, order = []
        for (const d of cameras.devices) {
            const c = d.category !== "" ? d.category : "?"
            if (!groups[c]) {
                groups[c] = []
                order.push(c)
            }
            groups[c].push(d)
        }
        return order.map(c => ({ title: c, items: groups[c] }))
    }

    //! The devices offered under an enumerated recipe.
    function devicesFor(kind: string): var {
        switch (kind) {
        case "camera":     return cameraGroups
        case "ndiin":      return ndi.devices
        case "pipewirein": return pipewire.devices
        case "gphoto2":    return gphoto.devices
        }
        return []
    }

    //! NodeCatalog.grouped() with each enumerated recipe's devices resolved.
    function menuModel(list: var): var {
        return NodeCatalog.grouped(list).map(g => ({
            title: g.title,
            items: g.items.map(r => ({
                recipe: r,
                devices: r.enumerate ? devicesFor(r.kind) : null,
                nested: r.kind === "camera"
            }))
        }))
    }

    //! Create a node for an enumerated device. A camera is named after the
    //! device rather than the capture mode.
    function pickDevice(recipe: var, dev: var) {
        const label = recipe.kind === "camera" && dev.category !== "" ? dev.category
                                                                      : dev.name
        NodeStore.create(recipe, dev.settings, label)
    }

    readonly property var sourceGroups:
        menuModel(NodeCatalog.sources.filter(r => !r.hidden))
    readonly property var destGroups:
        menuModel(NodeCatalog.destinations.filter(r => !r.hidden))

    CreateNodeDialog { id: createDialog }

    //! Create a node, asking for its fields first if it has any.
    function trigger(recipe) {
        if (NodeCatalog.fieldsOf(recipe).length > 0 || recipe.configPanel)
            createDialog.openFor(recipe)
        else
            NodeStore.create(recipe)
    }

    Shortcut { sequences: [StandardKey.Undo]; onActivated: HistoryStore.undo() }
    Shortcut { sequences: [StandardKey.Redo]; onActivated: HistoryStore.redo() }
    Shortcut {
        sequences: [StandardKey.Save]
        onActivated: {
            if (SessionStore.currentSession !== "")
                SessionStore.save(SessionStore.currentSession)
            else
                saveDialog.open()
        }
    }

    // ---- menus of the matrix toolbar ----
    Menu {
        id: sourceMenu
        Instantiator {
            model: mainWindow.sourceGroups
            delegate: NodeCategoryMenu {
                required property var modelData
                group: modelData
                onPicked: recipe => mainWindow.trigger(recipe)
                onPickedDevice: (recipe, dev) => mainWindow.pickDevice(recipe, dev)
            }
            onObjectAdded: (index, object) => sourceMenu.insertMenu(index, object)
            onObjectRemoved: (index, object) => sourceMenu.removeMenu(object)
        }
    }

    Menu {
        id: destMenu
        Instantiator {
            model: mainWindow.destGroups
            delegate: NodeCategoryMenu {
                required property var modelData
                group: modelData
                onPicked: recipe => mainWindow.trigger(recipe)
                onPickedDevice: (recipe, dev) => mainWindow.pickDevice(recipe, dev)
            }
            onObjectAdded: (index, object) => destMenu.insertMenu(index, object)
            onObjectRemoved: (index, object) => destMenu.removeMenu(object)
        }
    }

    Menu {
        id: sessionMenu
        MenuItem {
            text: Translations.t("New session")
            onTriggered: SessionStore.reset()
        }
        MenuItem {
            text: Translations.t("Save…")
            onTriggered: saveDialog.open()
        }
        Menu {
            title: Translations.t("Load")
            id: loadMenu
            property var names: []
            onAboutToShow: names = SessionStore.list()
            Repeater {
                model: loadMenu.names
                MenuItem {
                    required property string modelData
                    text: modelData
                    onTriggered: SessionStore.load(modelData)
                }
            }
            MenuItem {
                enabled: false
                visible: loadMenu.names.length === 0
                text: Translations.t("No saved session")
            }
        }
    }

    // ---- main layout: nav rail | content | status bar ----
    RowLayout {
        id: rootRow
        anchors.fill: parent
        spacing: 0

        NavRail {
            id: navRail
            Layout.fillHeight: true
            Layout.minimumWidth: 200
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            // Matrix toolbar: + Sources / + Destinations
            ToolBar {
                Layout.fillWidth: true
                visible: navRail.currentIndex === 0
                background: Rectangle { color: Style.background }
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Style.spacing
                    anchors.rightMargin: Style.spacing
                    spacing: Style.spacing

                    ScenicMenuButton {
                        text: "+ " + Translations.t("Sources")
                        onClicked: sourceMenu.popup(mapToItem(null, 0, height))
                    }
                    ScenicMenuButton {
                        text: "+ " + Translations.t("Destinations")
                        onClicked: destMenu.popup(mapToItem(null, 0, height))
                    }
                    Item { Layout.fillWidth: true }

                    ToolButton {
                        text: "↶"
                        ToolTip.text: Translations.t("Undo"); ToolTip.visible: hovered
                        enabled: HistoryStore.canUndo
                        onClicked: HistoryStore.undo()
                    }
                    ToolButton {
                        text: "↷"
                        ToolTip.text: Translations.t("Redo"); ToolTip.visible: hovered
                        enabled: HistoryStore.canRedo
                        onClicked: HistoryStore.redo()
                    }
                    ToolButton {
                        text: Translations.t("Peers")
                        onClicked: peersPanel.open()
                        Rectangle {
                            width: 8; height: 8; radius: 4
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: 4
                            color: WebRtcStore.connected ? Style.connected : Style.textDisabled
                        }
                    }
                    ToolButton {
                        text: Translations.t("Session")
                        onClicked: sessionMenu.popup(mapToItem(null, 0, height))
                    }
                }
            }

            SceneTabBar {
                Layout.fillWidth: true
                visible: navRail.currentIndex === 0
            }

            StackLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                currentIndex: navRail.currentIndex
                MatrixView {
                    onPreviewRequested: (nodeId) => preview.nodeId = nodeId
                }
                SettingsPage {}
                HelpPage {}
            }

            StatusBar { Layout.fillWidth: true }
        }
    }

    PreviewOverlay {
        id: preview
        anchors.fill: parent
        z: 100
    }

    InspectorDrawer { id: inspector }

    PeersPanel { id: peersPanel }

    // SCENIC_SCENARIO holds a filesystem path; Loader.setSource takes a URL. A
    // POSIX path only works by accident, and "D:\x\y.qml" parses as scheme "d".
    function scenarioUrl(path) {
        // Schemes are two characters or more, so a drive letter is not one.
        if (/^[a-zA-Z][a-zA-Z0-9+.-]+:/.test(path))
            return path
        if (!/^([a-zA-Z]:[\\/]|\\\\|\/)/.test(path))
            return path
        let p = path.replace(/\\/g, "/")
        if (p.charAt(0) !== "/")
            p = "/" + p
        // encodeURI keeps "/" and ":" but passes "#" and "?" through, and both
        // are legal in a file name.
        const enc = encodeURI(p).replace(/#/g, "%23").replace(/\?/g, "%3F")
        return (enc.startsWith("//") ? "file:" : "file://") + enc
    }

    // Test scenarios (tools/scenarios) run in this window when SCENIC_SCENARIO
    // holds the absolute path of one; see tools/run-tests.sh.
    Loader {
        id: scenario
        visible: false
    }

    ToastOverlay {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: Style.spacing * 2
        z: 200
    }

    Dialog {
        id: saveDialog
        title: Translations.t("Save session")
        modal: true
        anchors.centerIn: parent
        standardButtons: Dialog.Save | Dialog.Cancel
        onAccepted: if (saveName.text.length > 0) SessionStore.save(saveName.text)
        // pre-filled with the current name, selected so that typing replaces it
        onOpened: { saveName.forceActiveFocus(); saveName.selectAll() }
        TextField {
            id: saveName
            width: 240
            placeholderText: Translations.t("session name")
            text: SessionStore.currentSession
        }
    }
}
