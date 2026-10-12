import Scenic

NodeType {
    kind: "spoutin"
    label: Translations.t("Spout Input")
    role: "source"; mediaType: "video"; category: "Video In"; order: 100
    platforms: ["windows"]
    protocol: Uuids.spoutIn
    enumerate: true
    fields: [{ key: "path", label: Translations.t("Sender name"),
               type: "sourcename", protocol: Uuids.spoutIn, def: "", required: true,
               // receiving our own Spout output wedges the render graph
               exclude: n => NodeStore.isOwnSender("spoutout", n) }]
    makeSettings: p => ({ Path: p.path })
    addr: name => name + ":/"
}
