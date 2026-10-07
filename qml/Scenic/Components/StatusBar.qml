import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Scenic

// System load on the left, a summary of the matrix on the right.
Rectangle {
    id: bar
    height: 30
    color: Style.surface

    Rectangle { width: parent.width; height: 1; color: Style.background }  // top rule

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Style.spacing
        anchors.rightMargin: Style.spacing
        spacing: Style.spacing * 2

        RowLayout {
            spacing: 6
            Label {
                text: Translations.t("CPU"); color: Style.textDim
                font.pixelSize: Style.fontSizeSmall; font.bold: true
            }
            Rectangle {
                Layout.preferredWidth: 60
                Layout.preferredHeight: 8
                color: Style.item
                Rectangle {
                    width: parent.width * Math.min(1, StatsStore.cpuPercent / 100)
                    height: parent.height
                    color: StatsStore.cpuPercent > 90 ? Style.error
                         : StatsStore.cpuPercent > 70 ? Style.warning : Style.connected
                }
            }
            Label {
                text: StatsStore.cpuPercent.toFixed(0) + "%"
                color: Style.textDim; font.pixelSize: Style.fontSizeSmall
            }
        }

        Label {
            text: Translations.t("MEMORY") + " " + StatsStore.memPercent.toFixed(0) + "%"
            color: Style.textDim; font.pixelSize: Style.fontSizeSmall; font.bold: true
        }

        RowLayout {
            spacing: 6
            visible: StatsStore.netInterface !== ""
            Label {
                text: Translations.t("NETWORK"); color: Style.textDim
                font.pixelSize: Style.fontSizeSmall; font.bold: true
            }
            Label {
                text: StatsStore.netInterface
                      + "  ↓" + StatsStore.netRxKBps.toFixed(0)
                      + "  ↑" + StatsStore.netTxKBps.toFixed(0) + " KB/s"
                color: Style.textDim; font.pixelSize: Style.fontSizeSmall
            }
        }

        Item { Layout.fillWidth: true }

        Label {
            text: NodeStore.sources.count + " " + Translations.t("Sources").toLowerCase()
                  + " · " + NodeStore.destinations.count + " "
                  + Translations.t("Destinations").toLowerCase()
                  + " · " + Object.keys(MatrixStore.connections).length
                  + " " + Translations.t("Connections").toLowerCase()
            color: Style.textDisabled; font.pixelSize: Style.fontSizeSmall
        }
    }
}
