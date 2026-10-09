import Scenic

NodeType {
    kind: "spoutin"
    label: Translations.t("Spout Input")
    role: "source"; mediaType: "video"; category: "Video In"; order: 100; advanced: true
    platforms: ["windows"]
    protocol: Uuids.spoutIn
    fields: [{ key: "path", label: Translations.t("Sender name"), def: "Scenic" }]
    makeSettings: p => ({ Path: p.path })
    addr: name => name + ":/"
}
