import QtQuick

// A creatable source or destination. One file per type in Scenic/Nodes/,
// picked up by NodeCatalog.
QtObject {
    // ---- identity ----
    property string kind: ""                 // stable id, used in node ids and sessions
    property string label: ""
    property string role: "source"           // "source" | "destination"
    property string mediaType: "video"       // "video" | "audio" | "data"
    // menu group: one of score's protocol categories (NodeCatalog.categoryOrder)
    property string category: "Utilities"
    property int order: 100                  // position in menus and the matrix
    property bool hidden: false              // not offered in the menus
    property bool enumerate: false           // offered per enumerated device
    property var platforms: []               // Qt.platform.os values; empty = all

    // ---- engine binding ----
    property string protocol: ""             // device protocol uuid
    property string process: ""              // process uuid, for process-based types
    property var settings: null              // fixed device settings
    property string processData: ""          // fixed process data
    property var makeSettings: null          // params -> device settings
    property var makeProcessData: null       // params -> process data
    property var addr: null                  // device name -> address to bind
    // makeSettings also reads the app settings (ICE servers and their
    // credentials): a session saves the params only, and the settings are
    // made again when it is loaded.
    property bool derivedSettings: false

    // ---- data bridges ----
    // A transport makes this a BridgeStore socket instead of an engine node:
    // "udp" | "tcp" | "ws" | "serial" | "midi", with mediaType "data".
    property string transport: ""
    property string defaultCodec: "raw"      // "raw" | "osc" | "midi"

    // ---- UI ----
    // Creation and inspector fields:
    //   { key, label, type, def, min, max, options, placeholder, required,
    //     visibleWhen(values), platforms }
    // with type "string" (default) | "int" | "float" | "bool" | "enum" | "vec2"
    // | "file" | "savefile".
    // A field, or an enum option ({ value, label, platforms }), with
    // `platforms` exists only on those Qt.platform.os values; read the fields
    // through NodeCatalog.fieldsOf(), which applies that.
    property var fields: []
    // device-tree parameters edited live: { addr, label, type }
    property var deviceParams: []
    // optional panel replacing the generic field editors (a NodeConfig)
    property Component configPanel: null

    //! The entry of `values` for this OS, keyed by Qt.platform.os ("linux",
    //! "osx", "windows", ...), or its `default` entry: for defaults and option
    //! lists that differ per platform.
    function byPlatform(values) {
        return values[Qt.platform.os] ?? values["default"]
    }
}
