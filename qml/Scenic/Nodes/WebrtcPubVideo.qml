import Scenic

NodeType {
    kind: "webrtcpub_video"
    label: Translations.t("WebRTC Publish (video)")
    role: "destination"; mediaType: "video"; category: "Media"; order: 280
    protocol: Uuids.gstreamer
    derivedSettings: true
    fields: [
        { key: "uri", label: Translations.t("Signalling URI"), def: "ws://127.0.0.1:8443" },
        { key: "name", label: Translations.t("Stream name"), def: "video0" },
        { key: "peer", label: Translations.t("Peer name"), def: "scenic" }
    ]
    makeSettings: p => Pipelines.gstVideo("appsrc name=video ! videoconvert"
                  + " ! webrtcsink name=ws video-caps=video/x-h264"
                  + " meta=\"meta,name=(string)" + Pipelines.token(p.name)
                  + ",peer_name=(string)" + Pipelines.token(p.peer)
                  + ",media_type=(string)video\""
                  + " signaller::uri=" + Pipelines.quoted(p.uri)
                  + Pipelines.iceServers())
    addr: name => name + ":/Video"
}
