import Scenic

NodeType {
    kind: "audioin"
    label: Translations.t("System audio input")
    role: "source"; mediaType: "audio"; category: "Audio"; order: 50
    addr: name => "audio:/in/main"
}
