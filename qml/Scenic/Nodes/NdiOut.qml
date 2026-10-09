import Scenic

NodeType {
    kind: "ndiout"
    label: Translations.t("NDI® Output")
    role: "destination"; mediaType: "video"; category: "Video Out"; order: 230
    protocol: Uuids.ndiOut
    fields: [{ key: "path", label: Translations.t("Stream name"), def: "Scenic" }]
    makeSettings: p => ({ Path: p.path, Width: 1280, Height: 720, Rate: 30 })
    addr: name => name + ":/"
}
