import Scenic

NodeType {
    kind: "camera"
    label: Translations.t("Camera")
    role: "source"; mediaType: "video"; category: "Video In"; order: 10
    protocol: Uuids.camera
    enumerate: true
    addr: name => name + ":/"
}
