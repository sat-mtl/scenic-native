import Scenic

// Test-only: sine audio source at a chosen frequency for FFT checks.
NodeType {
    kind: "sine"; label: "Sine"; hidden: true; order: 910
    role: "source"; mediaType: "audio"; category: "Audio"
    protocol: Uuids.gstreamer
    fields: [{ key: "freq", label: "Freq", def: "440" }]
    makeSettings: p => Pipelines.gstAudioIn("audiotestsrc is-live=true wave=sine"
                  + " freq=" + p.freq + " volume=0.5"
                  + " ! audioconvert ! audio/x-raw,format=F32LE,rate=48000,channels=2"
                  + " ! appsink name=audio")
    addr: name => name + ":/audio"
}
