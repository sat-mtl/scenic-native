import QtQuick
import Scenic

// Media I/O through real devices, driven by tools/test-media.sh.
// SCENIC_MEDIA_PHASE=1: test pattern -> shmdata -> shmdata in -> SRT.
// SCENIC_MEDIA_PHASE=2: recording, video file playback, LTC to audio out.
Item {
    id: root
    property var shell
    property int step: 0
    Timer {
        interval: 1500
        repeat: true
        running: true
        onTriggered: {
            const phase = Util.environmentVariable("SCENIC_MEDIA_PHASE")
            root.step++
            const L = (m) => console.log("[mediaauto]", m)
            switch (root.step) {
            case 1: {
                if (phase === "1") {
                    NodeStore.create(NodeCatalog.recipe("videotest"))
                    const so = NodeCatalog.recipe("shmdataout")
                    NodeStore.create(so, so.makeSettings({ path: "/tmp/scenic_mloop" }))
                    L("videotest -> shmdataout: "
                      + MatrixStore.connect("src_videotest_1", "dst_shmdataout_2"))
                } else {
                    const clip = Util.environmentVariable("SCENIC_TEST_CLIP")
                    NodeStore.create(NodeCatalog.recipe("videotest"))
                    const rec = NodeCatalog.recipe("record")
                    NodeStore.create(rec, rec.makeSettings({ path: "/tmp/scenic_rec.mp4" }))
                    L("videotest -> record: "
                      + MatrixStore.connect("src_videotest_1", "dst_record_2"))
                    const fv = NodeCatalog.recipe("filevideo")
                    // a process-based type: params, no settings
                    NodeStore.create(fv, undefined, undefined, undefined, { path: clip })
                    const mon = NodeCatalog.recipe("window")
                    NodeStore.create(mon)
                    L("filevideo -> monitor: "
                      + MatrixStore.connect("src_filevideo_3", "dst_window_4"))
                    NodeStore.create(NodeCatalog.recipe("ltcgen"))
                    NodeStore.create(NodeCatalog.recipe("audioout"))
                    L("ltc -> audioout: "
                      + MatrixStore.connect("src_ltcgen_5", "dst_audioout_6"))
                    // and into a probe, whose file the suite checks for samples
                    const ap = NodeCatalog.recipe("audioprobe")
                    NodeStore.create(ap, ap.makeSettings({ path: "/tmp/scenic_ltc.raw" }))
                    L("ltc -> audioprobe: "
                      + MatrixStore.connect("src_ltcgen_5", "dst_audioprobe_7"))
                }
                break
            }
            case 2: {
                if (phase === "1") {
                    const si = NodeCatalog.recipe("shmdatain")
                    NodeStore.create(si, si.makeSettings({ path: "/tmp/scenic_mloop" }))
                    const srt = NodeCatalog.recipe("srt")
                    NodeStore.create(srt, srt.makeSettings({ uri: "srt://:4210?mode=listener" }))
                    L("shmdatain -> srt: "
                      + MatrixStore.connect("src_shmdatain_3", "dst_srt_4"))
                }
                break
            }
            case 12:
                if (phase === "2") {
                    L("closing record branch")
                    MatrixStore.disconnect("src_videotest_1", "dst_record_2")
                    NodeStore.remove("dst_record_2")
                }
                break
            case 14:
                L("DONE")
                Qt.exit(0)
                break
            default:
                break
            }
        }
    }
}
