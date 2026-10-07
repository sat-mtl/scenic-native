import Scenic

NodeType {
    kind: "wsout"
    label: Translations.t("WebSocket Output")
    role: "destination"; mediaType: "data"; category: "Web"; order: 420
    transport: "ws"
    // Bytes are sent as binary frames and decoded OSC as JSON text frames:
    // the WebSocket socket has no OSC encoder.
    fields: [
        { key: "host", label: Translations.t("Host"), def: "127.0.0.1" },
        { key: "port", label: Translations.t("Port"), type: "int", def: 9021, min: 1, max: 65535 }
    ]
}
