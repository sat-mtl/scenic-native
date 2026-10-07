pragma Singleton
import QtQuick

// Colours and metrics, from Scenic's "simon" theme
// (scenic/frontend/assets/themes/theme.simon.scss).
QtObject {
    readonly property string fontFamily: "Inter"

    // Primary palette
    readonly property color background: "#121212"
    readonly property color text: "#ebebeb"
    readonly property color textDim: "#8e8e8e"
    readonly property color textDisabled: "#505050"

    // Panel palette
    readonly property color surface: "#262626"
    readonly property color surfaceSelected: "#383838"
    readonly property color surfaceHovered: "#353535"

    // Item palette
    readonly property color item: "#383838"
    readonly property color itemSelected: "#454545"
    readonly property color itemHovered: "#505050"

    // Status palette
    readonly property color accent: "#7eb2c3"        // status-focus / primary
    readonly property color accentText: "#121212"
    readonly property color connected: "#38c566"     // status-active
    readonly property color error: "#d84b52"         // status-danger
    readonly property color warning: "#e7c900"       // status-busy

    readonly property color notification: "#ebebeb"
    readonly property color notificationText: "#121212"

    readonly property int windowWidth: 1600
    readonly property int windowHeight: 900
    readonly property int windowMinWidth: 1024
    readonly property int windowMinHeight: 600

    readonly property int spacing: 8
    readonly property int radius: 0
    readonly property int fontSize: 13
    readonly property int fontSizeSmall: 11
    readonly property int fontSizeLarge: 16
}
