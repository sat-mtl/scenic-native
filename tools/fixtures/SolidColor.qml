import Scenic

// Test-only: solid-color video source for exact mixing assertions.
NodeType {
    kind: "solidcolor"; label: "Solid Color"; hidden: true; order: 900
    role: "source"; mediaType: "video"; category: "Video"
    protocol: Uuids.gstreamer
    fields: [{ key: "color", label: "Color", def: "0xFFFF0000" }]
    makeSettings: p => Pipelines.gstVideo("videotestsrc is-live=true pattern=solid-color"
                  + " foreground-color=" + p.color
                  + " ! videoconvert ! video/x-raw,format=RGBA,width=1280,height=720"
                  + " ! appsink name=video")
    addr: name => name + ":/video"
}
