import Scenic

NodeType {
    kind: "tcpin"
    label: Translations.t("TCP Input")
    role: "source"; mediaType: "data"; category: "Network"; order: 310
    transport: "tcp"
    fields: [
        { key: "bind", label: Translations.t("Bind address"), def: "0.0.0.0" },
        { key: "port", label: Translations.t("Port"), type: "int", def: 9010, min: 1, max: 65535 },
        { key: "codec", label: Translations.t("Payload"), type: "enum", def: "raw",
          options: [ { value: "raw", label: Translations.t("Raw bytes") },
                     { value: "osc", label: Translations.t("OSC") } ] }
    ]
}
