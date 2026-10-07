import Scenic

NodeType {
    kind: "gstvideoout"
    label: Translations.t("GStreamer Pipeline (video out)")
    role: "destination"; mediaType: "video"; category: "Media"; order: 360
    protocol: Uuids.gstreamer
    // Frames arrive on `appsrc name=video`; the rest of the pipeline is yours.
    fields: [
        { key: "pipeline", label: Translations.t("Pipeline"),
          def: "appsrc name=video ! videoconvert ! autovideosink" },
        { key: "width", label: Translations.t("Width"), type: "int", def: 1280,
          min: 16, max: 7680 },
        { key: "height", label: Translations.t("Height"), type: "int", def: 720,
          min: 16, max: 4320 }
    ]
    makeSettings: p => Pipelines.gstVideo(p.pipeline, Number(p.width), Number(p.height))
    addr: name => name + ":/Video"
}
