import Scenic

NodeType {
    kind: "ffmpegin"
    label: Translations.t("FFmpeg Input")
    role: "source"; mediaType: "video"; category: "Media"; order: 352
    protocol: Uuids.libav
    // Anything libavformat can open: a file, a URL (rtsp://, srt://, rtmp://,
    // http://) or a lavfi filter graph.
    fields: [
        { key: "path", label: Translations.t("File, URL or lavfi graph"),
          def: "rtsp://127.0.0.1:8554/stream" },
        { key: "options", label: Translations.t("Options (key=value, …)"),
          def: "" }
    ]
    makeSettings: p => Pipelines.libavVideoIn(p.path, Pipelines.options(p.options))
    addr: name => name + ":/Video"
}
