import Scenic

NodeType {
    kind: "serialin"
    label: Translations.t("Serial Input")
    role: "source"; mediaType: "data"; category: "Hardware"; order: 330
    transport: "serial"
    fields: [
        { key: "device", label: Translations.t("Device"), def: byPlatform({ windows: "COM3", osx: "/dev/cu.usbserial", default: "/dev/ttyUSB0" }) },
        { key: "baud", label: Translations.t("Baud rate"), type: "int", def: 115200, min: 300, max: 4000000 },
        { key: "codec", label: Translations.t("Payload"), type: "enum", def: "raw",
          options: [ { value: "raw", label: Translations.t("Raw bytes") },
                     { value: "osc", label: Translations.t("OSC") } ] }
    ]
}
