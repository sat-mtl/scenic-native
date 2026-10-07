import Scenic

NodeType {
    kind: "shmdatain"
    label: Translations.t("Shmdata Input")
    role: "source"; mediaType: "video"; category: "Video In"; order: 80
    protocol: Uuids.shmdataIn
    platforms: ["linux", "osx"]
    fields: [{ key: "path", label: Translations.t("Socket path"), def: "/tmp/scenic_video" }]
    makeSettings: p => ({ Path: p.path })
    addr: name => name + ":/"
}
