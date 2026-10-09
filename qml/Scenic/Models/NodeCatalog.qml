pragma Singleton
import QtQuick

// The creatable node types. Every NodeType file in Scenic/Nodes/ is loaded at
// startup; adding a type means adding a file there. SCENIC_NODE_PATH names an
// extra directory to load, which the tests use for their probe types.
QtObject {
    id: root

    // all node types, then split by role; sorted by `order`, then label
    property var all: []
    property var sources: []
    property var destinations: []

    // score's order of Device::ProtocolFactory::StandardCategories, so the
    // menus read like score's device list
    readonly property var categoryOrder: [
        "Video In", "Video Out", "Video", "Audio", "Media",
        "Network", "Web", "Hardware", "Lights", "Tracking",
        "Software", "Utilities"
    ]

    Component.onCompleted: reload()

    function reload() {
        const urls = Util.listFiles(Util.urlToLocalFile(Qt.resolvedUrl("../Nodes")), "*.qml")
                         .map(f => Qt.resolvedUrl("../Nodes/" + f.split("/").pop()))
        const extra = Util.environmentVariable("SCENIC_NODE_PATH")
        if (extra !== "")
            for (const f of Util.listFiles(extra, "*.qml"))
                urls.push("file://" + f)

        const nodes = []
        for (const url of urls) {
            const comp = Qt.createComponent(url)
            if (comp.status !== Component.Ready) {
                console.error("NodeCatalog: failed to load", url, comp.errorString())
                continue
            }
            const obj = comp.createObject(root)
            if (obj && supported(obj))
                nodes.push(obj)
        }
        nodes.sort((a, b) => (a.order - b.order) || a.label.localeCompare(b.label))
        all = nodes
        sources = nodes.filter(n => n.role === "source")
        destinations = nodes.filter(n => n.role === "destination")
    }

    // Set by the pro package's environment-pro. Read once: the catalog is
    // built at startup and the flag cannot change under a running app.
    readonly property bool advancedIo: !!Util.environmentVariable("SAT_ADVANCED_IO")

    //! Whether a type's protocol exists on this OS and in this edition.
    function supported(n) {
        if (n.advanced && !advancedIo)
            return false
        return n.platforms.length === 0 || n.platforms.indexOf(Qt.platform.os) !== -1
    }

    //! A type's fields for this OS: fields and enum options that list
    //! `platforms` are kept only on those.
    function fieldsOf(recipe) {
        const here = e => !e.platforms || e.platforms.indexOf(Qt.platform.os) !== -1
        return (recipe ? recipe.fields ?? [] : [])
            .filter(here)
            .map(f => f.options ? Object.assign({}, f, { options: f.options.filter(here) }) : f)
    }

    //! `list` as [{ title, items }] in categoryOrder; unknown categories last.
    function grouped(list: var): var {
        const byCat = {}
        for (const r of list) {
            if (!byCat[r.category])
                byCat[r.category] = []
            byCat[r.category].push(r)
        }
        const out = []
        for (const c of categoryOrder) {
            if (byCat[c]) {
                out.push({ title: c, items: byCat[c] })
                delete byCat[c]
            }
        }
        for (const c in byCat)
            out.push({ title: c, items: byCat[c] })
        return out
    }

    function recipe(kind) {
        return all.find(n => n.kind === kind) ?? null
    }
}
