pragma Singleton
import QtQuick

QtObject {
    id: root

    property ListModel model: ListModel {}
    property int nextId: 0

    function notify(text, level) {
        model.append({ noteId: nextId++, text: text, level: level ?? "info" })
        if (model.count > 5)
            model.remove(0)
    }

    function info(text) { notify(text, "info") }
    function warn(text) { notify(text, "warn") }
    function error(text) { notify(text, "error") }

    function dismiss(noteId) {
        for (let i = 0; i < model.count; ++i)
            if (model.get(i).noteId === noteId) { model.remove(i); return }
    }
}
