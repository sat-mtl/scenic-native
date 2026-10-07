import Scenic

NodeType {
    kind: "ffmpegout"
    label: Translations.t("FFmpeg Output")
    role: "destination"; mediaType: "video"; category: "Media"; order: 362
    protocol: Uuids.libav
    // muxer and encoder by their ffmpeg short names
    fields: [
        { key: "path", label: Translations.t("File or URL"),
          def: SettingsStore.documentsDir + "/output.mkv" },
        { key: "muxer", label: Translations.t("Muxer"), def: "matroska" },
        { key: "encoder", label: Translations.t("Video encoder"), def: "libx264" },
        { key: "options", label: Translations.t("Options (key=value, …)"),
          def: "preset=veryfast, crf=23" }
    ]
    makeSettings: p => Pipelines.libavVideoOut(p.path, p.muxer, p.encoder,
                                               Pipelines.options(p.options))
    addr: name => name + ":/Video"
}
