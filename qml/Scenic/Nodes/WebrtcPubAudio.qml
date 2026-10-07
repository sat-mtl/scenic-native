import Scenic

NodeType {
    kind: "webrtcpub_audio"
    label: Translations.t("WebRTC Publish (audio)")
    role: "destination"; mediaType: "audio"; category: "Media"; order: 290
    protocol: Uuids.gstreamer
    derivedSettings: true
    fields: [
        { key: "uri", label: Translations.t("Signalling URI"), def: "ws://127.0.0.1:8443" },
        { key: "name", label: Translations.t("Stream name"), def: "audio0" },
        { key: "peer", label: Translations.t("Peer name"), def: "scenic" }
    ]
    makeSettings: p => Pipelines.gstAudioOut("webrtcsink name=ws"
                  + " meta=\"meta,name=(string)" + Pipelines.token(p.name)
                  + ",peer_name=(string)" + Pipelines.token(p.peer)
                  + ",media_type=(string)audio,channels=(int)2\""
                  + " signaller::uri=" + Pipelines.quoted(p.uri)
                  + Pipelines.iceServers())
    addr: name => name + ":/Audio"
}
