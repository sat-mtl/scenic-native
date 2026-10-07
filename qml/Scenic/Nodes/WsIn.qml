import Scenic

NodeType {
    kind: "wsin"
    label: Translations.t("WebSocket Input")
    role: "source"; mediaType: "data"; category: "Web"; order: 320
    transport: "ws"
    fields: [
        { key: "bind", label: Translations.t("Bind address"), def: "0.0.0.0" },
        { key: "port", label: Translations.t("Port"), type: "int", def: 9020, min: 1, max: 65535 },
        { key: "codec", label: Translations.t("Payload"), type: "enum", def: "raw",
          options: [ { value: "raw", label: Translations.t("Raw bytes") },
                     { value: "osc", label: Translations.t("OSC") } ] }
    ]
}
