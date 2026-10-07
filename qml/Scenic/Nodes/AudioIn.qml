import Scenic

NodeType {
    kind: "audioin"
    label: Translations.t("Audio Input")
    role: "source"; mediaType: "audio"; category: "Audio"; order: 50
    addr: name => "audio:/in/main"
}
