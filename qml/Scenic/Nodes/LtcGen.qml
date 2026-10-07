import Scenic

NodeType {
    kind: "ltcgen"
    label: Translations.t("LTC Generator")
    role: "source"; mediaType: "audio"; category: "Audio"; order: 60
    process: Uuids.ltcGen
}
