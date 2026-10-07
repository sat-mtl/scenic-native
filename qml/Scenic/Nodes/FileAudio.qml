import Scenic

NodeType {
    kind: "fileaudio"
    label: Translations.t("Audio File")
    role: "source"; mediaType: "audio"; category: "Media"; order: 110
    protocol: Uuids.gstreamer
    fields: [{ key: "path", label: Translations.t("File"), type: "file", def: "" }]
    makeSettings: p => Pipelines.gstAudioIn("filesrc location=" + Pipelines.quoted(p.path)
                  + " ! decodebin ! audioconvert ! audioresample"
                  + " ! audio/x-raw,format=F32LE,rate=48000,channels=2"
                  + " ! appsink name=audio")
    addr: name => name + ":/audio"
}
