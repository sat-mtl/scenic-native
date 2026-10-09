import Scenic

NodeType {
    kind: "ndiin"
    label: Translations.t("NDI® Input")
    role: "source"; mediaType: "video"; category: "Video In"; order: 70; advanced: true
    protocol: Uuids.ndiIn
    enumerate: true
    addr: name => name + ":/"
}
