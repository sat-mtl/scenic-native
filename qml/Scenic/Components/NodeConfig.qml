import QtQuick

// Base for a node's optional custom configuration panel. A NodeType may set
//   configPanel: Component { NodeConfig { … } }
// to provide its own editing UI instead of the generic FieldEditor list. The
// same panel is used by the create dialog and the inspector's settings section.
//
// Contract:
//   - read the current parameter values from `values` (reactive)
//   - call `edit(key, value)` whenever a field changes
Item {
    property var values: ({})
    signal edit(string key, var value)

    implicitWidth: childrenRect.width
    implicitHeight: childrenRect.height
}
