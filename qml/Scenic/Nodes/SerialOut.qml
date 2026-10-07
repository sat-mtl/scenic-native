import Scenic

NodeType {
    kind: "serialout"
    label: Translations.t("Serial Output")
    role: "destination"; mediaType: "data"; category: "Hardware"; order: 430
    transport: "serial"
    fields: [
        { key: "device", label: Translations.t("Device"), def: byPlatform({ windows: "COM3", osx: "/dev/cu.usbserial", default: "/dev/ttyUSB0" }) },
        { key: "baud", label: Translations.t("Baud rate"), type: "int", def: 115200, min: 300, max: 4000000 },
        { key: "codec", label: Translations.t("Payload"), type: "enum", def: "raw",
          options: [ { value: "raw", label: Translations.t("Raw bytes") },
                     { value: "osc", label: Translations.t("OSC") } ] }
    ]
}
