import QtQuick
import Scenic

// Populates the matrix for manual testing and screenshots. With
// SCENIC_SHOT=<path>, saves a screenshot of the window there and quits.
Item {
    id: root
    property var shell
    Timer {
        interval: 1000
        running: true
        onTriggered: {
            const mk = (kind, label, s) =>
                NodeStore.create(NodeCatalog.recipe(kind), s, label)
            mk("videotest", "Video Test Pattern")
            mk("audiotest", "Audio Test Signal")
            mk("windowcapture", "Screen capture",
               Pipelines.windowCapture(1))
            mk("shmdatain", "Studio shmdata camera feed 01",
               NodeCatalog.recipe("shmdatain").makeSettings({ path: "/tmp/cam01" }))
            mk("window", "Video Monitor")
            mk("audioout", "Audio Output")
            mk("ndiout", "Studio NDI Stream",
               NodeCatalog.recipe("ndiout").makeSettings({ path: "Scenic" }))
            mk("rtmp", "Live Broadcast",
               NodeCatalog.recipe("rtmp").makeSettings({ url: "rtmp://live.example.org/app", key: "stream" }))
            mk("shmdataout", "Shmdata Output",
               NodeCatalog.recipe("shmdataout").makeSettings({ path: "/tmp/scenic_demo" }))
            MatrixStore.connect("src_videotest_1", "dst_window_5")
            MatrixStore.connect("src_windowcapture_3", "dst_window_5")
            MatrixStore.connect("src_videotest_1", "dst_ndiout_7")
            MatrixStore.connect("src_audiotest_2", "dst_audioout_6")
            SceneStore.addScene("Concert Main")
            NodeStore.selectedNodeId = "dst_window_5"
            if (Util.environmentVariable("SCENIC_SHOT") !== "")
                shotTimer.start()
        }
    }

    Timer {
        id: shotTimer
        interval: 3500
        onTriggered: {
            const path = Util.environmentVariable("SCENIC_SHOT")
            root.shell.contentItem.grabToImage(result => {
                result.saveToFile(path)
                console.log("[shot] saved", path)
                Qt.exit(0)
            })
        }
    }
}
