import Scenic

NodeType {
    kind: "ndiin"
    label: Translations.t("NDI® Input")
    role: "source"; mediaType: "video"; category: "Video In"; order: 70
    protocol: Uuids.ndiIn
    enumerate: true
    // Discovery is asynchronous and can fail outright behind a firewall; the
    // receiver connects by name as soon as the sender shows up, so the name
    // stays typable.
    fields: [{ key: "path", label: Translations.t("Source name"),
               type: "sourcename", protocol: Uuids.ndiIn, def: "", required: true }]
    makeSettings: p => ({ Path: p.path })
    addr: name => name + ":/"
}
