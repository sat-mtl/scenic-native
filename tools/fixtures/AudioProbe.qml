import Scenic

// Test-only: GStreamer output writing raw S16LE audio to a file. Hidden.
NodeType {
    kind: "audioprobe"; label: "Audio Probe"; hidden: true; order: 910
    role: "destination"; mediaType: "audio"; category: "Utilities"
    protocol: Uuids.gstreamer
    fields: [{ key: "path", label: "File", def: "/tmp/scenic_probe.raw" }]
    // S16LE stereo at 48 kHz, which is what tools/check-frame.py reads
    makeSettings: p => Pipelines.gstAudioOut(
                  "audio/x-raw,format=S16LE,rate=48000,channels=2"
                  + " ! filesink location=" + Pipelines.quoted(p.path))
    addr: name => name + ":/Audio"
}
