import Scenic

NodeType {
    kind: "pipewirein"
    label: Translations.t("PipeWire Input")
    role: "source"; mediaType: "video"; category: "Video In"; order: 102
    platforms: ["linux"]
    protocol: Uuids.pipewireIn
    // The protocol enumerates the live PipeWire video nodes, so the menu lists
    // what is publishing rather than asking for a name to guess.
    enumerate: true
    addr: name => name + ":/"
}
