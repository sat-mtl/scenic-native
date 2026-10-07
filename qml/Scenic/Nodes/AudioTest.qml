import Scenic

NodeType {
    kind: "audiotest"
    label: Translations.t("Audio Test Signal")
    role: "source"; mediaType: "audio"; category: "Audio"; order: 40
    protocol: Uuids.gstreamer
    settings: Pipelines.gstAudioIn("audiotestsrc is-live=true wave=sine freq=440 volume=0.2"
              + " ! audioconvert ! audio/x-raw,format=F32LE,rate=48000,channels=2"
              + " ! appsink name=audio")
    addr: name => name + ":/audio"
}
