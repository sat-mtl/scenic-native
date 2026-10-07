import Scenic

NodeType {
    kind: "gphoto2"
    label: Translations.t("Photo Camera")
    role: "source"; mediaType: "video"; category: "Video In"; order: 11
    protocol: Uuids.gphoto2
    // Settings are a {model, port} pair only libgphoto2 can supply.
    enumerate: true
    addr: name => name + ":/"
}
