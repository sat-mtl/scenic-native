import Scenic

NodeType {
    kind: "midiin"
    label: Translations.t("MIDI Input")
    role: "source"; mediaType: "data"; category: "Hardware"; order: 340
    transport: "midi"; defaultCodec: "midi"
    fields: [
        { key: "device", label: Translations.t("Port"), def: "",
          placeholder: Translations.t("first available") },
        { key: "codec", label: Translations.t("Payload"), type: "enum", def: "midi",
          options: [
            { value: "midi", label: Translations.t("MIDI (as /midi/… OSC)") },
            { value: "raw", label: Translations.t("Raw bytes") }
          ] }
    ]
}
