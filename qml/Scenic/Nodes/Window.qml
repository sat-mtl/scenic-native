import Scenic

NodeType {
    kind: "window"
    label: Translations.t("Video Monitor")
    role: "destination"; mediaType: "video"; category: "Video Out"; order: 210
    protocol: Uuids.window
    settings: ({})
    addr: name => name + ":/"
    // live device-tree parameters (written via Device.write)
    deviceParams: [
        { addr: "/position",   label: Translations.t("Position"),   type: "vec2" },
        { addr: "/size",       label: Translations.t("Size"),       type: "vec2" },
        { addr: "/fullscreen", label: Translations.t("Fullscreen"), type: "bool" }
    ]
}
