import Scenic

NodeType {
    kind: "syphonout"
    label: Translations.t("Syphon Output")
    role: "destination"; mediaType: "video"; category: "Video Out"; order: 261; advanced: true
    platforms: ["osx"]
    protocol: Uuids.syphonOut
    fields: [{ key: "path", label: Translations.t("Server name"), def: "Scenic" }]
    makeSettings: p => ({ Path: p.path, Width: 1280, Height: 720, Rate: 30 })
    addr: name => name + ":/"
}
