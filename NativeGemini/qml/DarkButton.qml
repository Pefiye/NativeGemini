import QtQuick
import QtQuick.Controls
import QtQuick.Controls.impl

Button {
    id: root

    implicitHeight: 48
    font.pixelSize: 14
    palette.buttonText: "white"

    contentItem: Row {
        spacing: root.icon.source.toString().length > 0 && root.text.length > 0 ? 8 : 0
        anchors.centerIn: parent

        ColorImage {
            width: root.icon.source.toString().length > 0 ? 20 : 0
            height: 20
            anchors.verticalCenter: parent.verticalCenter
            source: root.icon.source
            color: "white"
            sourceSize.width: 20
            sourceSize.height: 20
            fillMode: Image.PreserveAspectFit
            visible: root.icon.source.toString().length > 0
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.text
            color: "white"
            font: root.font
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            visible: root.text.length > 0
        }
    }

    background: Rectangle {
        radius: 8
        color: root.enabled ? (root.down ? "#211D2B" : root.hovered ? "#342E43" : "#241F31") : "#2A2536"
        border.color: root.hovered ? "#6A5E82" : "#41384F"
        border.width: 1
    }
}
