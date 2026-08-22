import QtQuick
import QtQuick.Controls

ComboBox {
    id: root

    font.pixelSize: 15
    textRole: ""

    function prettyText(value) {
        var text = String(value || "")
        if (text.indexOf("models/") === 0)
            text = text.slice(7)
        text = text.replace(/[-_]+/g, " ")
        return text.replace(/\b\w/g, function(letter) {
            return letter.toUpperCase()
        })
    }

    contentItem: Text {
        leftPadding: 18
        rightPadding: 44
        text: root.prettyText(root.currentText)
        color: "white"
        font: root.font
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }

    indicator: Text {
        anchors.right: parent.right
        anchors.rightMargin: 16
        anchors.verticalCenter: parent.verticalCenter
        text: root.popup.visible ? "⌃" : "⌄"
        color: "white"
        font.pixelSize: 24
        verticalAlignment: Text.AlignVCenter
    }

    background: Rectangle {
        radius: 8
        color: root.enabled ? (root.hovered ? "#342E43" : "#241F31") : "#2A2536"
        border.color: root.hovered ? "#6A5E82" : "#41384F"
        border.width: 1
    }

    delegate: ItemDelegate {
        width: root.width
        height: 44
        text: modelData
        font: root.font

        contentItem: Text {
            text: root.prettyText(parent.text)
            color: "white"
            font: parent.font
            elide: Text.ElideRight
            verticalAlignment: Text.AlignVCenter
        }

        background: Rectangle {
            color: parent.hovered ? "#342E43" : "#241F31"
        }
    }

    popup: Popup {
        y: root.height + 6
        width: root.width
        implicitHeight: Math.min(contentItem.implicitHeight, 260)
        padding: 0

        contentItem: ListView {
            clip: true
            implicitHeight: contentHeight
            model: root.popup.visible ? root.delegateModel : null
            currentIndex: root.highlightedIndex
        }

        background: Rectangle {
            radius: 8
            color: "#241F31"
            border.color: "#41384F"
            border.width: 1
        }
    }
}
