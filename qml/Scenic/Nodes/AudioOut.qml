import Scenic

NodeType {
    kind: "audioout"
    label: Translations.t("System audio output")
    role: "destination"; mediaType: "audio"; category: "Audio"; order: 220
    addr: name => "audio:/out/main"
}
