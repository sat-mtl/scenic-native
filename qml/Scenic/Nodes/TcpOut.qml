import Scenic

NodeType {
    kind: "tcpout"
    label: Translations.t("TCP Output")
    role: "destination"; mediaType: "data"; category: "Network"; order: 410
    transport: "tcp"
    fields: [
        { key: "host", label: Translations.t("Host"), def: "127.0.0.1" },
        { key: "port", label: Translations.t("Port"), type: "int", def: 9011, min: 1, max: 65535 },
        { key: "codec", label: Translations.t("Payload"), type: "enum", def: "raw",
          options: [ { value: "raw", label: Translations.t("Raw bytes") },
                     { value: "osc", label: Translations.t("OSC") } ] }
    ]
}
