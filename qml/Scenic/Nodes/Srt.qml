import Scenic

NodeType {
    kind: "srt"
    label: Translations.t("SRT Streaming")
    role: "destination"; mediaType: "video"; category: "Media"; order: 270
    protocol: Uuids.libav
    // A listener blocks the engine until a peer connects: listen_timeout (in
    // microseconds) bounds that wait, after which the output gives up.
    fields: [{ key: "uri", label: Translations.t("SRT URI"),
               def: "srt://:4200?mode=listener&listen_timeout=5000000" }]
    makeSettings: p => Pipelines.libavVideoOut(p.uri, "mpegts", "libx264",
                  [["preset", "ultrafast"], ["tune", "zerolatency"], ["flush_packets", "1"]])
    addr: name => name + ":/Video"
}
