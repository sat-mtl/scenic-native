import Scenic

NodeType {
    kind: "pipewireout"
    label: Translations.t("PipeWire Output")
    role: "destination"; mediaType: "video"; category: "Video Out"; order: 262
    platforms: ["linux"]
    protocol: Uuids.pipewireOut
    // Publishes a Video/Source node any PipeWire consumer picks up: OBS, a
    // browser, ffplay -f pipewire.
    fields: [{ key: "path", label: Translations.t("Node name"), def: "Scenic" }]
    makeSettings: p => ({ Path: p.path, Width: 1280, Height: 720, Rate: 30 })
    addr: name => name + ":/"
}
