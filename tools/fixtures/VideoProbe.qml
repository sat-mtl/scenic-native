import Scenic

// Test-only: GStreamer output writing JPEG frames to a file so integration
// tests can assert on actual routed pixels. Hidden. (tools/test-routing.sh)
NodeType {
    kind: "videoprobe"; label: "Video Probe"; hidden: true; order: 900
    role: "destination"; mediaType: "video"; category: "Utilities"
    protocol: Uuids.gstreamer
    fields: [{ key: "path", label: "File", def: "/tmp/scenic_probe.jpg" }]
    makeSettings: p => Pipelines.gstVideo("appsrc name=video ! videoconvert"
                  + " ! video/x-raw,format=RGB ! jpegenc"
                  + " ! filesink location=" + Pipelines.quoted(p.path))
    addr: name => name + ":/Video"
}
