import Scenic

NodeType {
    kind: "record"
    label: Translations.t("Record to File")
    role: "destination"; mediaType: "video"; category: "Media"; order: 300
    protocol: Uuids.libav
    fields: [{ key: "path", label: Translations.t("File"), type: "savefile",
               def: SettingsStore.documentsDir + "/recording.mp4" }]
    makeSettings: p => Pipelines.libavVideoOut(p.path, "mp4", "libx264",
                  [["preset", "veryfast"], ["crf", "23"]])
    addr: name => name + ":/Video"
}
