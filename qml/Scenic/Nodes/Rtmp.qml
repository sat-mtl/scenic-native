import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Scenic

NodeType {
    kind: "rtmp"
    label: Translations.t("RTMP Streaming")
    role: "destination"; mediaType: "video"; category: "Media"; order: 260
    protocol: Uuids.libav
    // the fields give the defaults; configPanel below edits them
    fields: [
        { key: "url", label: Translations.t("Stream URL"), def: "rtmp://a.rtmp.youtube.com/live2" },
        { key: "key", label: Translations.t("Stream key"), def: "", required: true }
    ]
    makeSettings: p => Pipelines.libavVideoOut(p.url + "/" + p.key, "flv", "libx264",
                   [["preset", "veryfast"], ["tune", "zerolatency"], ["g", "60"]])
    addr: name => name + ":/Video"

    // The two fields and the resulting URL, with the key masked.
    configPanel: Component {
        NodeConfig {
            id: cfg
            ColumnLayout {
                width: parent.width
                spacing: Style.spacing
                FieldEditor {
                    Layout.fillWidth: true
                    field: ({ label: Translations.t("Stream URL"), type: "string" })
                    value: cfg.values.url
                    onEdited: v => cfg.edit("url", v)
                }
                FieldEditor {
                    Layout.fillWidth: true
                    field: ({ label: Translations.t("Stream key"), type: "string" })
                    value: cfg.values.key
                    onEdited: v => cfg.edit("key", v)
                }
                Label {
                    Layout.fillWidth: true
                    text: Translations.t("Publishing to: ") + (cfg.values.url ?? "")
                          + "/" + "•".repeat(Math.min(8, (cfg.values.key ?? "").length))
                    color: Style.textDim
                    font.pixelSize: Style.fontSizeSmall
                    elide: Text.ElideMiddle
                }
            }
        }
    }
}
