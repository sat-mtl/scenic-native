import QtQuick
import Scenic

// Engine-level checks of what the app's design relies on: devices can be
// added while playing, ISF hubs can be created, bound and cabled, and a
// webrtcsrc pipeline parses. Loaded by Main.qml (SCENIC_SCENARIO).
Item {
    id: spikes

    property var shell
    readonly property string gstUuid: Uuids.gstreamer

    property var lastProcess: null

    function log(msg) { console.log("[spike]", msg) }

    property int autoStep: 0
    property int autoBad: 0
    Timer {
        id: autoTimer
        interval: 1500
        repeat: true
        running: true
        onTriggered: {
            spikes.autoStep++
            const A = (cond, m) => { if (!cond) { spikes.autoBad++
                                                 spikes.log("AUTO FAIL: " + m) } }
            // one swallowed exception per tick would otherwise let the run reach
            // DONE having proven nothing
            try {
            switch (spikes.autoStep) {
            case 1: {
                const procs = Score.availableProcesses()
                const entries = Object.entries(procs)
                spikes.log("AUTO1 availableProcesses count=" + entries.length)
                spikes.log("AUTO1 first entry: " + JSON.stringify(entries[0]))
                Util.writeFile("/tmp/scenic-spike-processes.json",
                               JSON.stringify(procs, null, 1))
                spikes.log("AUTO1 full dump -> /tmp/scenic-spike-processes.json")
                A(entries.length > 0, "availableProcesses() returned nothing")
                A(Util.fileExists("/tmp/scenic-spike-processes.json"),
                  "the process dump was not written")
                break
            }
            case 2:
                Score.play()
                spikes.log("AUTO2 play() ok")
                break
            case 3:
                A(Score.device("spike_gst_1") === null,
                  "spike_gst_1 already exists before we create it")
                Score.createDevice("spike_gst_1", spikes.gstUuid, {
                    Pipeline: "videotestsrc is-live=true ! videoconvert"
                              + " ! video/x-raw,format=RGBA ! appsink name=video",
                    Width: 640, Height: 480, Rate: 30,
                    AudioChannels: 0, InputTransfer: 13
                })
                spikes.log("AUTO3 hot-added GStreamer device while playing")
                // the point of this spike: a device can be added while playing
                A(Score.device("spike_gst_1") !== null,
                  "hot-adding a device while playing did not produce one")
                break
            case 4: {
                // Hub = ISF Shader process with a passthrough shader.
                Util.writeFile("/tmp/scenic-passthrough.fs",
                    "/*{ \"CATEGORIES\": [\"Utility\"],"
                    + " \"INPUTS\": [ { \"NAME\": \"inputImage\", \"TYPE\": \"image\" } ] }*/\n"
                    + "void main() { gl_FragColor = IMG_THIS_PIXEL(inputImage); }\n")
                const p = Score.createProcess(Score.rootInterval(),
                    Uuids.isf, "/tmp/scenic-passthrough.fs")
                spikes.log("AUTO4 createProcess(ISF passthrough) -> " + p)
                A(p !== null, "createProcess(ISF) returned null - the hub pattern"
                              + " this app is built on does not work")
                if (p) {
                    spikes.lastProcess = p
                    Score.setName(p, "spike_hub_1")
                    spikes.log("AUTO4 inlets=" + Score.inlets(p) + " outlets=" + Score.outlets(p))
                    const inl = Score.port(p, "inputImage") ?? Score.inlet(p, 0)
                    Score.setAddress(inl, "spike_gst_1:/video")
                    spikes.log("AUTO4 inputImage bound to spike_gst_1:/video")
                }
                break
            }
            case 5: {
                const p2 = Score.createProcess(Score.rootInterval(),
                    Uuids.isf, "/tmp/scenic-passthrough.fs")
                if (spikes.lastProcess && p2) {
                    const cable = Score.createCable(Score.outlet(spikes.lastProcess, 0),
                                                    Score.port(p2, "inputImage") ?? Score.inlet(p2, 0))
                    spikes.log("AUTO5 createCable hub->hub -> " + cable)
                    A(cable !== null, "hub->hub cable could not be created")
                } else {
                    spikes.log("AUTO5 SKIP (missing processes)")
                    A(false, "AUTO5 could not run: a hub process is missing")
                }
                break
            }
            case 6: {
                let pipe = "webrtcsrc name=ws"
                    + " signaller::uri=ws://127.0.0.1:8443"
                const pid = Util.environmentVariable("SCENIC_SPIKE_PRODUCER")
                if (pid.length > 0)
                    pipe += " signaller::producer-peer-id=" + pid
                pipe += " ! videoconvert ! video/x-raw,format=RGBA ! appsink name=video"
                Score.createDevice("spike_webrtc_1", spikes.gstUuid, {
                    Pipeline: pipe, Width: 1280, Height: 720, Rate: 30,
                    AudioChannels: 0, InputTransfer: 13
                })
                spikes.log("AUTO6 webrtcsrc device created (parse + child props ok if no error above)")
                A(Score.device("spike_webrtc_1") !== null,
                  "the webrtcsrc device was not created")
                break
            }
            case 7: case 8: case 9: case 10:
                // let the WebRTC connection establish and frames flow
                spikes.log("AUTO" + spikes.autoStep + " waiting for webrtc media...")
                break
            default:
                spikes.log("AUTO checked with " + spikes.autoBad + " problem(s)")
                if (spikes.autoBad > 0) {
                    Qt.exit(1)
                    break
                }
                spikes.log("AUTO DONE")
                autoTimer.running = false
                Qt.exit(0)
            }
            } catch (e) {
                spikes.autoBad++
                spikes.log("AUTO FAIL: step " + spikes.autoStep + " threw " + e)
            }
        }
    }
}
