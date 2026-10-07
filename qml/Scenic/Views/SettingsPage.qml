import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Scenic

Item {
    ColumnLayout {
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.margins: Style.spacing * 3
        anchors.topMargin: Style.spacing * 3
        spacing: Style.spacing * 2
        width: 480

        Label {
            text: Translations.t("General")
            color: Style.accent
            font.pixelSize: Style.fontSizeLarge
            font.bold: true
        }

        RowLayout {
            Label {
                text: Translations.t("Language")
                color: Style.text
                Layout.preferredWidth: 180
            }
            ComboBox {
                model: ["English", "Français"]
                currentIndex: SettingsStore.language === "fr" ? 1 : 0
                onActivated: {
                    SettingsStore.language = currentIndex === 1 ? "fr" : "en"
                    SettingsStore.save()
                }
            }
        }

        RowLayout {
            Label {
                text: Translations.t("Show thumbnails")
                color: Style.text
                Layout.preferredWidth: 180
            }
            Switch {
                checked: SettingsStore.showThumbnails
                onToggled: {
                    SettingsStore.showThumbnails = checked
                    SettingsStore.save()
                }
            }
        }

        Label {
            text: Translations.t("Telepresence")
            color: Style.accent
            font.pixelSize: Style.fontSizeLarge
            font.bold: true
        }

        RowLayout {
            Label {
                text: Translations.t("Peer name")
                color: Style.text
                Layout.preferredWidth: 180
            }
            TextField {
                Layout.fillWidth: true
                text: SettingsStore.peerName
                onEditingFinished: {
                    SettingsStore.peerName = text
                    SettingsStore.save()
                }
            }
        }

        RowLayout {
            Label {
                text: Translations.t("Signalling server")
                color: Style.text
                Layout.preferredWidth: 180
            }
            TextField {
                Layout.fillWidth: true
                text: SettingsStore.signallerUri
                onEditingFinished: {
                    SettingsStore.signallerUri = text
                    SettingsStore.save()
                }
            }
        }

        RowLayout {
            Label {
                text: Translations.t("Access token")
                color: Style.text
                Layout.preferredWidth: 180
            }
            TextField {
                Layout.fillWidth: true
                echoMode: TextInput.PasswordEchoOnEdit
                text: SettingsStore.authToken
                onEditingFinished: {
                    SettingsStore.authToken = text
                    SettingsStore.save()
                }
            }
        }

        RowLayout {
            Label {
                text: Translations.t("STUN server")
                color: Style.text
                Layout.preferredWidth: 180
            }
            TextField {
                Layout.fillWidth: true
                placeholderText: "stun://host:3478"
                text: SettingsStore.stunServer
                onEditingFinished: {
                    SettingsStore.stunServer = text
                    SettingsStore.save()
                }
            }
        }

        RowLayout {
            Label {
                text: Translations.t("TURN server")
                color: Style.text
                Layout.preferredWidth: 180
            }
            TextField {
                Layout.fillWidth: true
                placeholderText: "turn://host:3478"
                text: SettingsStore.turnServer
                onEditingFinished: {
                    SettingsStore.turnServer = text
                    SettingsStore.save()
                }
            }
        }

        RowLayout {
            Label {
                text: Translations.t("TURN username")
                color: Style.text
                Layout.preferredWidth: 180
            }
            TextField {
                Layout.fillWidth: true
                text: SettingsStore.turnUser
                onEditingFinished: {
                    SettingsStore.turnUser = text
                    SettingsStore.save()
                }
            }
        }

        RowLayout {
            Label {
                text: Translations.t("TURN password")
                color: Style.text
                Layout.preferredWidth: 180
            }
            TextField {
                Layout.fillWidth: true
                echoMode: TextInput.PasswordEchoOnEdit
                text: SettingsStore.turnPassword
                onEditingFinished: {
                    SettingsStore.turnPassword = text
                    SettingsStore.save()
                }
            }
        }
    }
}
