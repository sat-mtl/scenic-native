import Scenic

NodeType {
    kind: "windowcapture"
    label: Translations.t("Screen / Window Capture")
    role: "source"; mediaType: "video"; category: "Video In"; order: 20
    protocol: Uuids.windowCapture
    fields: [
        { key: "mode", label: Translations.t("Capture"), type: "enum", def: 1,
          options: [
            { value: 1, label: Translations.t("All Screens") },
            { value: 2, label: Translations.t("Single Screen") },
            { value: 0, label: Translations.t("A Window") },
            { value: 3, label: Translations.t("Screen Region") }
          ] },
        { key: "title", label: Translations.t("Window title"), type: "string", def: "",
          visibleWhen: v => Number(v.mode) === 0 },
        { key: "screen", label: Translations.t("Screen name"), type: "string", def: "",
          visibleWhen: v => Number(v.mode) === 2 },
        { key: "rpos", label: Translations.t("Region X, Y"), type: "vec2", def: [0, 0],
          visibleWhen: v => Number(v.mode) === 3 },
        { key: "rsize", label: Translations.t("Region W, H"), type: "vec2", def: [640, 480],
          visibleWhen: v => Number(v.mode) === 3 }
    ]
    makeSettings: p => {
        const pos = p.rpos ?? [0, 0], sz = p.rsize ?? [640, 480]
        return Pipelines.windowCapture(Number(p.mode), p.title, p.screen,
            { x: Number(pos[0]) || 0, y: Number(pos[1]) || 0,
              w: Number(sz[0]) || 0, h: Number(sz[1]) || 0 })
    }
    addr: name => name + ":/"
}
