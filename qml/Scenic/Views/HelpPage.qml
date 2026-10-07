import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Scenic

Item {
    ColumnLayout {
        anchors.centerIn: parent
        spacing: Style.spacing * 2
        width: 520

        Label {
            text: "Scenic"
            color: Style.accent
            font.pixelSize: 32
            font.bold: true
            Layout.alignment: Qt.AlignHCenter
        }

        Label {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
            color: Style.text
            text: Translations.t("Real-time transmission of audiovisual and arbitrary data "
                  + "over IP networks, for telepresence in artistic contexts.")
        }

        Label {
            Layout.alignment: Qt.AlignHCenter
            color: Style.textDim
            font.pixelSize: Style.fontSizeSmall
            text: "Scenic Native — " + Translations.t("engine: ossia score")
        }

        ColumnLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 2

            Repeater {
                model: [
                    { label: Translations.t("Scenic documentation"),
                      url: "https://sat-mtl.github.io/scenic-native/"
                           + (Translations.language === "fr" ? "fr/" : "en/") },
                    { label: "ossia score", url: "https://ossia.io" },
                    { label: "Société des Arts Technologiques", url: "https://sat.qc.ca" },
                    { label: Translations.t("Report an issue"),
                      url: "https://github.com/sat-mtl/scenic-native/issues" }
                ]
                delegate: Label {
                    required property var modelData
                    Layout.alignment: Qt.AlignHCenter
                    text: "<a href=\"" + modelData.url + "\">" + modelData.label + "</a>"
                    textFormat: Text.RichText
                    color: Style.text
                    linkColor: Style.accent
                    onLinkActivated: (link) => Qt.openUrlExternally(link)
                }
            }
        }

        Label {
            Layout.alignment: Qt.AlignHCenter
            color: Style.textDim
            font.pixelSize: Style.fontSizeSmall
            text: "GPL-3.0-or-later — © Société des Arts Technologiques"
        }
    }
}
