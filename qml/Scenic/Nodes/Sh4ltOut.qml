import Scenic

NodeType {
    kind: "sh4ltout"
    label: Translations.t("Sh4lt Output")
    role: "destination"; mediaType: "video"; category: "Video Out"; order: 250
    protocol: Uuids.sh4ltOut
    platforms: ["linux"]
    fields: [{ key: "path", label: Translations.t("Stream name"), def: "scenic" }]
    makeSettings: p => ({ Path: p.path, Width: 1280, Height: 720, Rate: 30 })
    addr: name => name + ":/"
}
