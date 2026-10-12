import Scenic

NodeType {
    kind: "videotest"
    label: Translations.t("Video Test Pattern")
    role: "source"; mediaType: "video"; category: "Utility"; order: 30
    protocol: Uuids.gstreamer
    settings: Pipelines.gstVideo("videotestsrc is-live=true pattern=smpte ! videoconvert"
              + " ! video/x-raw,format=RGBA,width=1280,height=720 ! appsink name=video")
    addr: name => name + ":/video"
}
