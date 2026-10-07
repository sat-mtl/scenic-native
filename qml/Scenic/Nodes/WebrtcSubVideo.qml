import Scenic

NodeType {
    kind: "webrtcsub_video"; label: Translations.t("WebRTC Video"); hidden: true; order: 920
    role: "source"; mediaType: "video"; category: "Media"
    protocol: Uuids.gstreamer
    derivedSettings: true
    fields: [
        { key: "uri", label: Translations.t("Signalling URI"), def: "ws://127.0.0.1:8443" },
        { key: "producerId", label: Translations.t("Producer id"), def: "" , required: true }
    ]
    makeSettings: p => Pipelines.gstVideo("webrtcsrc name=ws"
                  + " signaller::uri=" + Pipelines.quoted(p.uri)
                  + " signaller::producer-peer-id=" + Pipelines.quoted(p.producerId)
                  + Pipelines.iceServers()
                  + " ! videoconvert ! video/x-raw,format=RGBA ! appsink name=video")
    addr: name => name + ":/video"
}
