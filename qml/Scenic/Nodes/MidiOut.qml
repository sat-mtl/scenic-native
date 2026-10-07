import Scenic

NodeType {
    kind: "midiout"
    label: Translations.t("MIDI Output")
    role: "destination"; mediaType: "data"; category: "Hardware"; order: 440
    transport: "midi"; defaultCodec: "midi"
    fields: [
        { key: "device", label: Translations.t("Port"), def: "",
          placeholder: Translations.t("first available") },
        { key: "codec", label: Translations.t("Payload"), type: "enum", def: "midi",
          options: [
            { value: "midi", label: Translations.t("MIDI (from /midi/… OSC)") },
            { value: "raw", label: Translations.t("Raw bytes") }
          ] }
    ]
}
