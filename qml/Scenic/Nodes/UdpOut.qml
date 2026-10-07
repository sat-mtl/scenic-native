import Scenic

NodeType {
    kind: "udpout"
    label: Translations.t("UDP Output")
    role: "destination"; mediaType: "data"; category: "Network"; order: 400
    transport: "udp"
    fields: [
        { key: "host", label: Translations.t("Host"), def: "127.0.0.1" },
        { key: "port", label: Translations.t("Port"), type: "int", def: 9001, min: 1, max: 65535 },
        { key: "codec", label: Translations.t("Payload"), type: "enum", def: "raw",
          options: [ { value: "raw", label: Translations.t("Raw bytes") },
                     { value: "osc", label: Translations.t("OSC") } ] }
    ]
}
