pragma Singleton
import QtQuick

// score device-protocol and process UUIDs, shared by the node definitions.
//
// Not named Protocols: the score script engine puts libossia's qml_protocols
// (raw OSC / MIDI / UDP / TCP sockets) in the global object under that name,
// and a Scenic singleton of the same name shadows it in every file that
// imports Scenic.
QtObject {
    // devices
    readonly property string gstreamer: "2c644357-16a4-4c25-9e27-8e5c4a9a647d"
    readonly property string camera: "d615690b-f2e2-447b-b70e-a800552db69c"
    readonly property string window: "5a181207-7d40-4ad8-814e-879fcdf8cc31"
    readonly property string windowCapture: "a7c1e3f0-5d2b-4e8a-9f6c-1b3d5e7a9c0f"
    readonly property string ndiIn: "ae78b7c6-6400-483e-b45b-fd6ff87ec700"
    readonly property string ndiOut: "07651c13-83de-48b8-a450-abe2891051e8"
    readonly property string shmdataIn: "8062b2e5-c589-41f1-8977-96c5ba782f95"
    readonly property string shmdataOut: "69bb8215-dae2-4ec9-b60c-79f4f4fc2390"
    readonly property string sh4ltIn: "7b3a7adb-af9e-4dd5-9bd7-641f4d33fa2d"
    readonly property string sh4ltOut: "41e367e1-fc36-40b2-b8c4-8aecd5dfd4fc"
    readonly property string libav: "8b3e4f2a-1d5c-4e7b-a9f3-6c2d8e4b1a7f"
    readonly property string spoutIn: "3c995cb6-052b-4c52-a8fd-841b33b81b29"
    readonly property string spoutOut: "ddf45db7-9eaf-453c-8fc0-86ccdf21677c"
    readonly property string syphonIn: "398cec01-c4ea-43b7-8281-d848748e0f68"
    readonly property string syphonOut: "087d032d-9a42-4bc9-b3df-ad9ba9e86c07"
    readonly property string pipewireIn: "cf6a355f-34d1-4d24-a6ea-3d204f93cde9"
    readonly property string pipewireOut: "d5e7b22b-b7f6-4680-9610-2457509b7946"
    readonly property string gphoto2: "a7e5e6cc-3e7e-4f92-b5f6-0dca37e64c8a"

    // processes (hubs / sources)
    readonly property string isf: "74ca45ff-92c9-44a0-8f1a-754dea05ee1b"
    readonly property string gain: "6c158669-0f81-41c9-8cc6-45820dcda867"
    readonly property string ltcGen: "f87bec01-d2c1-4bdf-bda7-792bc62b0c49"
    readonly property string video: "32dc5341-7748-4c31-a226-82e6bd685744"
}
