import Scenic

NodeType {
    kind: "webrtcsub_audio"; label: Translations.t("WebRTC Audio"); hidden: true; order: 930
    role: "source"; mediaType: "audio"; category: "Media"
    protocol: Uuids.gstreamer
    derivedSettings: true
    fields: [
        { key: "uri", label: Translations.t("Signalling URI"), def: "ws://127.0.0.1:8443" },
        { key: "producerId", label: Translations.t("Producer id"), def: "" , required: true }
    ]
    makeSettings: p => Pipelines.gstAudioIn("webrtcsrc name=ws"
                  + " signaller::uri=" + Pipelines.quoted(p.uri)
                  + " signaller::producer-peer-id=" + Pipelines.quoted(p.producerId)
                  + Pipelines.iceServers()
                  + " ! audioconvert ! audioresample"
                  + " ! audio/x-raw,format=F32LE,rate=48000,channels=2"
                  + " ! appsink name=audio")
    addr: name => name + ":/audio"
}
