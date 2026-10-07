import Scenic

NodeType {
    kind: "gstaudioin"
    label: Translations.t("GStreamer Pipeline (audio in)")
    role: "source"; mediaType: "audio"; category: "Media"; order: 351
    protocol: Uuids.gstreamer
    // the pipeline must end in an F32LE `appsink name=audio`
    fields: [
        { key: "pipeline", label: Translations.t("Pipeline"),
          def: "audiotestsrc ! audioconvert ! audioresample"
             + " ! audio/x-raw,format=F32LE,rate=48000,channels=2"
             + " ! appsink name=audio" }
    ]
    makeSettings: p => Pipelines.gstAudioIn(p.pipeline)
    addr: name => name + ":/audio"
}
