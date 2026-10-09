import Scenic

NodeType {
    kind: "syphonin"
    label: Translations.t("Syphon Input")
    role: "source"; mediaType: "video"; category: "Video In"; order: 101
    platforms: ["osx"]
    protocol: Uuids.syphonIn
    fields: [{ key: "path", label: Translations.t("Server name"), def: "Scenic" }]
    makeSettings: p => ({ Path: p.path })
    addr: name => name + ":/"
}
