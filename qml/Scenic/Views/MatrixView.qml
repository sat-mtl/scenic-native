pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic
import Scenic

// The routing matrix: destinations as columns, sources as rows. Clicking a
// head selects the node, clicking a cell toggles the connection.
//
// A column head reads horizontally: rotated text cannot be bounded by the
// column it labels, so a long name always escaped into its neighbours. It is
// shrunk to fit instead, down to minimumHeadFont, and elided below that.
Item {
    id: matrixView

    signal previewRequested(string nodeId)

    readonly property int headW: 240
    readonly property int cellW: 112
    readonly property int rowH: 64
    readonly property int bandH: 54
    readonly property int minimumHeadFont: 8

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

                // Corner with the DESTINATIONS caption. Horizontal like the
                // heads it labels, and there is no room for a diagonal in a
                // band this short.
                Item {
                    width: matrixView.headW
                    height: matrixView.bandH
                    Label {
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.margins: 8
                        text: Translations.t("DESTINATIONS")
                        color: Style.textDim
                        font.pixelSize: Style.fontSizeSmall
                        font.bold: true
                        font.letterSpacing: 2
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

                        Column {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            anchors.leftMargin: 4
                            anchors.rightMargin: 4
                            anchors.bottomMargin: 7
                            spacing: 1

                            Label {
                                width: parent.width
                                text: destHead.model.label
                                color: destHead.selected ? Style.accent
                                     : destHead.active ? Style.text : Style.textDim
                                font.pixelSize: Style.fontSizeSmall
                                font.bold: true
                                fontSizeMode: Text.HorizontalFit
                                minimumPixelSize: matrixView.minimumHeadFont
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideRight
                            }
                            Label {
                                width: parent.width
                                visible: text !== ""
                                text: destHead.model.typeLabel
                                color: Style.textDisabled
                                font.pixelSize: Style.fontSizeSmall - 1
                                fontSizeMode: Text.HorizontalFit
                                minimumPixelSize: matrixView.minimumHeadFont - 1
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideRight
                            }
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
                        // a shrunk or elided head is not readable: always offer
                        // the full name
                        ToolTip.text: destHead.model.typeLabel !== ""
                                    ? destHead.model.label + " — " + destHead.model.typeLabel
                                    : destHead.model.label
                        ToolTip.visible: headHover.hovered
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
