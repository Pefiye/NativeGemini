import QtQuick
import QtQuick.Controls
import QtQuick.Controls.impl

Button {
    id: root
    property url source
    property string tooltip: ""
    property int iconSize: Math.min(width * 0.58, 32)

    width: 48
    height: 48
    text: ""

    contentItem: ColorImage {
        source: root.source
        color: "white"
        sourceSize.width: root.iconSize
        sourceSize.height: root.iconSize
        fillMode: Image.PreserveAspectFit
        horizontalAlignment: Image.AlignHCenter
        verticalAlignment: Image.AlignVCenter
    }

    background: Rectangle {
        radius: 8
        color: root.enabled ? (root.down ? "#272235" : root.hovered ? "#383149" : "#241F31") : "#2A2536"
        border.color: root.hovered ? "#6A5E82" : "#41384F"
        border.width: 1
    }

    ToolTip.visible: hovered && tooltip.length > 0
    ToolTip.text: tooltip
}
