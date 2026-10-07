import Scenic

NodeType {
    kind: "gstaudioout"
    label: Translations.t("GStreamer Pipeline (audio out)")
    role: "destination"; mediaType: "audio"; category: "Media"; order: 361
    protocol: Uuids.gstreamer
    // what follows `appsrc name=audio ! audioconvert ! audioresample`
    fields: [
        { key: "tail", label: Translations.t("Pipeline (after the source)"),
          def: "audioconvert ! autoaudiosink" },
        { key: "channels", label: Translations.t("Channels"), type: "int", def: 2,
          min: 1, max: 64 }
    ]
    makeSettings: p => Pipelines.gstAudioOut(p.tail, Number(p.channels))
    addr: name => name + ":/Audio"
}
