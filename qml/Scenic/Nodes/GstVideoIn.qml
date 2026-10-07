import Scenic

NodeType {
    kind: "gstvideoin"
    label: Translations.t("GStreamer Pipeline (video in)")
    role: "source"; mediaType: "video"; category: "Media"; order: 350
    protocol: Uuids.gstreamer
    // the pipeline must end in `appsink name=video`, the address bound below
    fields: [
        { key: "pipeline", label: Translations.t("Pipeline"),
          def: "videotestsrc ! videoconvert ! video/x-raw,format=RGBA ! appsink name=video" },
        { key: "width", label: Translations.t("Width"), type: "int", def: 1280,
          min: 16, max: 7680 },
        { key: "height", label: Translations.t("Height"), type: "int", def: 720,
          min: 16, max: 4320 }
    ]
    makeSettings: p => Pipelines.gstVideo(p.pipeline, Number(p.width), Number(p.height))
    addr: name => name + ":/video"
}
