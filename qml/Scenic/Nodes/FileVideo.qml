import Scenic

// score's video file process, looping, cabled into the source chain.
NodeType {
    kind: "filevideo"
    label: Translations.t("Video File")
    role: "source"; mediaType: "video"; category: "Media"; order: 100
    process: Uuids.video
    fields: [{ key: "path", label: Translations.t("File"), type: "file", def: "" }]
    makeProcessData: p => p.path
}
