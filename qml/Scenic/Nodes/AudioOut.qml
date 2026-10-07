import Scenic

NodeType {
    kind: "audioout"
    label: Translations.t("Audio Output")
    role: "destination"; mediaType: "audio"; category: "Audio"; order: 220
    addr: name => "audio:/out/main"
}
