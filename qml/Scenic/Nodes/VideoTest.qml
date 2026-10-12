import QtQuick
import Scenic

NodeType {
    kind: "videotest"
    label: Translations.t("Video Test Pattern")
    role: "source"; mediaType: "video"; category: "Utility"; order: 30
    // An ISF generator rather than a GStreamer pipeline: the pattern an
    // operator reaches for to prove the chain works must not itself depend on
    // a runtime that is not shipped with the app on every platform.
    process: Uuids.isf
    processData: Util.urlToLocalFile(Qt.resolvedUrl("../shaders/testpattern.fs"))
}
