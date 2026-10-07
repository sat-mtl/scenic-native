import Scenic

NodeType {
    kind: "sh4ltin"
    label: Translations.t("Sh4lt Input")
    role: "source"; mediaType: "video"; category: "Video In"; order: 90
    protocol: Uuids.sh4ltIn
    platforms: ["linux"]
    fields: [{ key: "path", label: Translations.t("Stream name"), def: "scenic" }]
    makeSettings: p => ({ Path: p.path })
    addr: name => name + ":/"
}
