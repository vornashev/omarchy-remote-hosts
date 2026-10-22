import QtQuick
import QtQuick.Shapes

Item {
    id: root
    property color color: "white"
    property color alertColor: "red"
    // One signal at a time, by priority: alert, checking, mounted, private, idle.
    property string mode: "idle"
    property real pulse: 1

    readonly property bool solid: mode === "private"
    // The status holes are transparent, so any bar background shows through.
    readonly property string topPath: "M3 3H13A1 1 0 0 1 14 4V6A1 1 0 0 1 13 7H3A1 1 0 0 1 2 6V4A1 1 0 0 1 3 3Z"
        + (solid ? "" : " M6 5A1 1 0 1 0 4 5A1 1 0 1 0 6 5Z")
    // The alert badge sits in a transparent notch cut from the lower plate.
    readonly property string bottomPath: (mode === "alert"
        ? "M3 9H13A1 1 0 0 1 14 10V10.04A3.5 3.5 0 0 0 10.04 13H3A1 1 0 0 1 2 12V10A1 1 0 0 1 3 9Z"
        : "M3 9H13A1 1 0 0 1 14 10V12A1 1 0 0 1 13 13H3A1 1 0 0 1 2 12V10A1 1 0 0 1 3 9Z")
        + (solid ? "" : " M6 11A1 1 0 1 0 4 11A1 1 0 1 0 6 11Z")
    readonly property color bottomColor: mode === "mounted" ? Qt.darker(color, 1.4)
                                       : mode === "checking" ? Qt.darker(color, 2.0) : color

    SequentialAnimation on pulse {
        running: root.mode === "checking"
        loops: Animation.Infinite
        NumberAnimation { to: 0.35; duration: 700; easing.type: Easing.InOutSine }
        NumberAnimation { to: 1; duration: 700; easing.type: Easing.InOutSine }
    }

    // G9fACu: a 12 px stack centered in the bar's 16 px canvas.
    Item {
        anchors.centerIn: parent
        width: 16
        height: 16
        scale: Math.min(root.width, root.height) / 16
        opacity: root.mode === "checking" ? 0.55 : 1

        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                fillColor: root.color
                fillRule: ShapePath.OddEvenFill
                strokeColor: "transparent"
                strokeWidth: 0
                PathSvg { path: root.topPath }
            }
        }
        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            opacity: root.mode === "checking" ? root.pulse : 1
            ShapePath {
                fillColor: root.bottomColor
                fillRule: ShapePath.OddEvenFill
                strokeColor: "transparent"
                strokeWidth: 0
                PathSvg { path: root.bottomPath }
            }
        }
        Rectangle {
            visible: root.mode === "alert"
            x: 11
            y: 11
            width: 5
            height: 5
            radius: 2.5
            color: root.alertColor
            antialiasing: true
        }
    }
}
