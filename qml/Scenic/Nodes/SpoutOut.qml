import Scenic

NodeType {
    kind: "spoutout"
    label: Translations.t("Spout Output")
    role: "destination"; mediaType: "video"; category: "Video Out"; order: 260; advanced: true
    platforms: ["windows"]
    protocol: Uuids.spoutOut
    fields: [{ key: "path", label: Translations.t("Sender name"), def: "Scenic" }]
    makeSettings: p => ({ Path: p.path, Width: 1280, Height: 720, Rate: 30 })
    addr: name => name + ":/"
}
