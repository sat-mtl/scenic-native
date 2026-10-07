import Scenic

NodeType {
    kind: "udpin"
    label: Translations.t("UDP Input")
    role: "source"; mediaType: "data"; category: "Network"; order: 300
    transport: "udp"
    fields: [
        { key: "bind", label: Translations.t("Bind address"), def: "0.0.0.0" },
        { key: "port", label: Translations.t("Port"), type: "int", def: 9000, min: 1, max: 65535 },
        { key: "codec", label: Translations.t("Payload"), type: "enum", def: "raw",
          options: [ { value: "raw", label: Translations.t("Raw bytes") },
                     { value: "osc", label: Translations.t("OSC") } ] }
    ]
}
