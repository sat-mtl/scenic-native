pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic
import Scenic

// The routing matrix: destinations as columns under slanted headers, sources
// as rows. Clicking a head selects the node, clicking a cell toggles the
// connection.
Item {
    id: matrixView

    signal previewRequested(string nodeId)

    readonly property int headW: 240
    readonly property int cellW: 80
    readonly property int rowH: 64
    readonly property int bandH: 150

    Flickable {
        anchors.fill: parent
        anchors.margins: Style.spacing
        contentWidth: grid.width
        contentHeight: grid.height
        clip: true
        ScrollBar.vertical: ScrollBar {}
        ScrollBar.horizontal: ScrollBar {}

        Column {
            id: grid
            spacing: 2

            // ---- Header band: corner + diagonal destination heads ----
            Row {
                spacing: 2
                z: 2

                // Corner with the diagonal DESTINATIONS caption
                Item {
                    width: matrixView.headW
                    height: matrixView.bandH
                    Label {
                        text: Translations.t("DESTINATIONS")
                        color: Style.textDim
                        font.pixelSize: Style.fontSizeSmall
                        font.bold: true
                        rotation: -45
                        // BottomLeft pivots on (x, y + height)
                        transformOrigin: Item.BottomLeft
                        x: parent.width - 130
                        y: parent.height - height - 6
                    }
                }

                Repeater {
                    model: NodeStore.destinations
                    delegate: Item {
                        id: destHead
                        required property var model
                        width: matrixView.cellW
                        height: matrixView.bandH
                        clip: false

                        readonly property bool active:
                            MatrixStore.connectionsOf(model.nodeId).length > 0
                        readonly property bool selected:
                            NodeStore.selectedNodeId === model.nodeId

                        // faint hover / selected column tint
                        Rectangle {
                            anchors.fill: parent
                            color: destHead.selected
                                 ? Qt.rgba(Style.accent.r, Style.accent.g, Style.accent.b, 0.14)
                                 : headHover.hovered ? Qt.rgba(1, 1, 1, 0.05) : "transparent"
                        }

                        // Rotated about (x, y + height). At -60 degrees a
                        // 110px label spans about width/2 + height horizontally,
                        // which stays within one column.
                        Label {
                            text: destHead.model.label
                            color: destHead.selected ? Style.accent
                                 : destHead.active ? Style.text : Style.textDim
                            font.pixelSize: Style.fontSizeSmall
                            font.bold: true
                            renderType: Text.QtRendering
                            rotation: -60
                            transformOrigin: Item.BottomLeft
                            x: 10
                            y: parent.height - height - 16
                            width: 110
                            elide: Text.ElideRight
                        }
                        Label {
                            text: destHead.model.typeLabel
                            color: Style.textDisabled
                            font.pixelSize: Style.fontSizeSmall - 1
                            renderType: Text.QtRendering
                            rotation: -60
                            transformOrigin: Item.BottomLeft
                            x: 10
                            y: parent.height - height - 4
                            width: 110
                            elide: Text.ElideRight
                        }

                        // active underline at the column top
                        Rectangle {
                            anchors.bottom: parent.bottom
                            width: parent.width - 2
                            height: destHead.selected ? 3 : 2
                            color: destHead.selected ? Style.accent
                                 : destHead.active ? Style.connected : Style.item
                        }

                        HoverHandler { id: headHover }
                        ToolTip.text: destHead.model.label
                        ToolTip.visible: headHover.hovered && destHead.model.label.length > 16
                        MouseArea {
                            anchors.fill: parent
                            onClicked: NodeStore.selectedNodeId =
                                (NodeStore.selectedNodeId === destHead.model.nodeId
                                 ? "" : destHead.model.nodeId)
                        }
                    }
                }
            }

            // ---- SOURCES panel header ----
            Rectangle {
                width: matrixView.headW
                height: 26
                color: Style.item
                visible: NodeStore.sources.count > 0
                Label {
                    anchors.centerIn: parent
                    text: Translations.t("SOURCES")
                    color: Style.textDim
                    font.pixelSize: Style.fontSizeSmall
                    font.bold: true
                    font.letterSpacing: 2
                }
            }

            // ---- Source rows ----
            Repeater {
                model: NodeStore.sources
                delegate: Row {
                    id: sourceRow
                    required property var model
                    spacing: 2

                    NodeHead {
                        width: matrixView.headW
                        height: matrixView.rowH
                        nodeId: sourceRow.model.nodeId
                        label: sourceRow.model.label
                        typeLabel: sourceRow.model.typeLabel
                        mediaType: sourceRow.model.mediaType
                        onPreviewRequested: (id) => matrixView.previewRequested(id)
                    }

                    Repeater {
                        model: NodeStore.destinations
                        delegate: Rectangle {
                            id: cell
                            required property var model
                            readonly property string srcId: sourceRow.model.nodeId ?? ""
                            readonly property string dstId: model.nodeId
                            readonly property bool isCompatible:
                                sourceRow.model.mediaType === model.mediaType
                            readonly property bool isConnected:
                                MatrixStore.isConnected(srcId, dstId)

                            width: matrixView.cellW
                            height: matrixView.rowH
                            color: !isCompatible ? Style.background
                                 : cellMouse.containsMouse ? Style.surfaceHovered
                                 : Style.surface

                            // chevron when connected
                            Canvas {
                                anchors.centerIn: parent
                                width: 30; height: 20
                                visible: cell.isConnected
                                onPaint: {
                                    const ctx = getContext("2d")
                                    ctx.reset()
                                    ctx.strokeStyle = Style.connected
                                    ctx.lineWidth = 4
                                    ctx.lineCap = "round"
                                    ctx.lineJoin = "round"
                                    ctx.beginPath()
                                    ctx.moveTo(3, 15)
                                    ctx.lineTo(15, 4)
                                    ctx.lineTo(27, 15)
                                    ctx.stroke()
                                }
                            }

                            // dot on a cell that can be connected
                            Rectangle {
                                anchors.centerIn: parent
                                width: 4; height: 4; radius: 2
                                color: Style.item
                                visible: cell.isCompatible && !cell.isConnected
                                         && !cellMouse.containsMouse
                            }

                            MouseArea {
                                id: cellMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                enabled: cell.isCompatible
                                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                onClicked: MatrixStore.toggle(cell.srcId, cell.dstId)
                            }
                        }
                    }
                }
            }
        }
    }

    Label {
        anchors.centerIn: parent
        visible: NodeStore.sources.count === 0 && NodeStore.destinations.count === 0
        text: Translations.t("No sources or destinations yet.\nUse  + Sources  and  + Destinations  to add some.")
        color: Style.textDim
        horizontalAlignment: Text.AlignHCenter
    }
}
