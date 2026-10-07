import Scenic

NodeType {
    kind: "shmdataout"
    label: Translations.t("Shmdata Output")
    role: "destination"; mediaType: "video"; category: "Video Out"; order: 240
    protocol: Uuids.shmdataOut
    platforms: ["linux", "osx"]
    fields: [{ key: "path", label: Translations.t("Socket path"), def: "/tmp/scenic_out" }]
    makeSettings: p => ({ Path: p.path, Width: 1280, Height: 720, Rate: 30 })
    addr: name => name + ":/"
}
