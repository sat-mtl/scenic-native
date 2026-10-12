import Scenic

NodeType {
    kind: "syphonin"
    label: Translations.t("Syphon Input")
    role: "source"; mediaType: "video"; category: "Video In"; order: 101
    platforms: ["osx"]
    protocol: Uuids.syphonIn
    enumerate: true
    fields: [{ key: "path", label: Translations.t("Server name"),
               type: "sourcename", protocol: Uuids.syphonIn, def: "", required: true,
               exclude: n => NodeStore.isOwnSender("syphonout", n) }]
    makeSettings: p => ({ Path: p.path })
    addr: name => name + ":/"
}
