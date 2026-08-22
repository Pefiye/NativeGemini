import QtQuick
import QtQuick.Controls
import QtQuick.Controls.impl

Rectangle {
    id: root
    property int minComposerHeight: 82
    property int maxComposerHeight: 190
    readonly property int framePadding: 24
    readonly property int attachmentStripHeight: appController.pendingImages.length > 0 ? 72 : 0
    readonly property real desiredComposerHeight: input.contentHeight + framePadding
    readonly property string groundingMode: appController.groundingMode
    readonly property string groundingLabel: groundingMode === "always" ? "Always ground" : groundingMode === "off" ? "Grounding off" : "Auto grounding"
    readonly property url groundingIcon: groundingMode === "always"
        ? Qt.resolvedUrl("../../Icons/Search_Magnifying_Glass.svg")
        : groundingMode === "off"
            ? Qt.resolvedUrl("../../Icons/Cloud_Off.svg")
            : Qt.resolvedUrl("../../Icons/Planet.svg")

    function focusComposer() {
        input.forceActiveFocus()
        input.cursorPosition = input.text.length
    }

    height: attachmentStripHeight + Math.min(maxComposerHeight, Math.max(minComposerHeight, desiredComposerHeight))
    radius: 10
    color: "#CC211D31"
    border.color: "#41384F"
    border.width: 1

    AppFilePicker {
        id: filePicker
        title: "Attach files"
        folderMode: false
        nameFilters: ["*.png", "*.jpg", "*.jpeg", "*.webp", "*.heic", "*.heif", "*.txt", "*.md", "*.markdown"]
        onFilesAccepted: function(urls) {
            appController.addFileAttachments(urls)
        }
    }

    Flickable {
        id: attachmentStrip
        anchors.left: parent.left
        anchors.right: grounding.left
        anchors.top: parent.top
        anchors.leftMargin: 12
        anchors.rightMargin: 12
        anchors.topMargin: 10
        height: root.attachmentStripHeight > 0 ? 58 : 0
        visible: height > 0
        clip: true
        contentWidth: attachmentRow.width
        contentHeight: height
        contentX: Math.min(contentX, Math.max(0, contentWidth - width))
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.HorizontalFlick

        ScrollBar.horizontal: ScrollBar {
            policy: attachmentStrip.contentWidth > attachmentStrip.width ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
        }

        Row {
            id: attachmentRow
            height: parent.height
            spacing: 8

            Repeater {
                model: appController.pendingImages

                delegate: Rectangle {
                    readonly property bool isImageAttachment: modelData.kind === "image"

                    width: isImageAttachment ? 58 : 168
                    height: 58
                    radius: 8
                    color: "#241F31"
                    border.color: "#41384F"
                    border.width: 1
                    clip: true

                    Image {
                        visible: parent.isImageAttachment
                        anchors.fill: parent
                        anchors.margins: 3
                        source: modelData.url
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                    }

                    Row {
                        visible: !parent.isImageAttachment
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 9

                        Rectangle {
                            width: 42
                            height: 42
                            radius: 8
                            color: "#332D43"
                            border.color: "#514761"
                            border.width: 1

                            Text {
                                anchors.centerIn: parent
                                text: modelData.extension
                                color: "white"
                                font.pixelSize: modelData.extension.length > 3 ? 10 : 12
                                font.weight: Font.DemiBold
                                elide: Text.ElideRight
                                maximumLineCount: 1
                            }
                        }

                        Column {
                            width: parent.width - 51
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2

                            Text {
                                width: parent.width
                                text: modelData.name
                                color: "white"
                                font.pixelSize: 13
                                elide: Text.ElideRight
                                maximumLineCount: 1
                            }

                            Text {
                                width: parent.width
                                text: Math.max(1, Math.ceil(modelData.size / 1024)) + " KB"
                                color: "#BDB5D2"
                                font.pixelSize: 11
                                elide: Text.ElideRight
                            }
                        }
                    }

                    ToolTip.visible: thumbMouse.containsMouse
                    ToolTip.text: modelData.name + " - click to remove"

                    MouseArea {
                        id: thumbMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: appController.removePendingImage(modelData.id)
                    }
                }
            }
        }
    }

    ScrollView {
        id: inputScroll
        anchors.left: parent.left
        anchors.right: grounding.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.leftMargin: 12
        anchors.rightMargin: 12
        anchors.topMargin: root.attachmentStripHeight + 12
        anchors.bottomMargin: 12
        clip: true
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        ScrollBar.vertical.policy: input.contentHeight > inputScroll.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff

        TextArea {
            id: input
            width: inputScroll.availableWidth
            height: Math.max(inputScroll.height, contentHeight)
            color: "white"
            placeholderText: "Ask Gemini"
            placeholderTextColor: "#CFC9DF"
            wrapMode: TextArea.Wrap
            font.pixelSize: 18
            selectByMouse: true
            background: Rectangle {
                radius: 8
                color: "#241F31"
                border.color: input.activeFocus ? "#6A5E82" : "transparent"
                border.width: 1
            }
            Keys.onPressed: function(event) {
                if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_V && appController.addClipboardAttachment()) {
                    event.accepted = true
                }
            }
            Keys.onReturnPressed: function(event) {
                if (event.modifiers & Qt.ShiftModifier) {
                    input.insert(input.cursorPosition, "\n")
                    event.accepted = true
                    return
                }
                appController.sendPrompt(input.text)
                input.text = ""
                event.accepted = true
            }
        }
    }

    IconButton {
        id: grounding
        anchors.right: attach.left
        anchors.bottom: parent.bottom
        anchors.rightMargin: 10
        anchors.bottomMargin: 12
        width: 52
        height: 52
        source: root.groundingIcon
        tooltip: root.groundingLabel
        onClicked: groundingPopup.open()
    }

    Popup {
        id: groundingPopup
        width: 210
        x: Math.max(0, grounding.x + grounding.width - width)
        y: -height - 8
        padding: 8
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

        background: Rectangle {
            radius: 8
            color: "#211D31"
            border.color: "#41384F"
            border.width: 1
        }

        contentItem: Column {
            spacing: 4

            Repeater {
                model: [
                    {"mode": "auto", "label": "Auto", "icon": "../../Icons/Planet.svg"},
                    {"mode": "always", "label": "Always", "icon": "../../Icons/Search_Magnifying_Glass.svg"},
                    {"mode": "off", "label": "Off", "icon": "../../Icons/Cloud_Off.svg"}
                ]

                delegate: Button {
                    id: modeButton
                    width: groundingPopup.width - groundingPopup.padding * 2
                    height: 40
                    text: modelData.label
                    icon.source: Qt.resolvedUrl(modelData.icon)
                    icon.color: "white"
                    icon.width: 18
                    icon.height: 18
                    font.pixelSize: 15
                    palette.buttonText: "white"
                    onClicked: {
                        appController.setGroundingMode(modelData.mode)
                        groundingPopup.close()
                    }

                    contentItem: Row {
                        anchors.fill: parent
                        anchors.leftMargin: 14
                        anchors.rightMargin: 12
                        spacing: 8

                        Item {
                            width: 24
                            height: parent.height

                            ColorImage {
                                anchors.centerIn: parent
                                width: 18
                                height: 18
                                source: modeButton.icon.source
                                color: "white"
                                sourceSize.width: 18
                                sourceSize.height: 18
                                fillMode: Image.PreserveAspectFit
                            }
                        }

                        Text {
                            width: parent.width - 24 - parent.spacing
                            anchors.verticalCenter: parent.verticalCenter
                            text: modeButton.text
                            color: "white"
                            font.pixelSize: modeButton.font.pixelSize
                            elide: Text.ElideRight
                        }
                    }

                    background: Rectangle {
                        radius: 7
                        color: modeButton.hovered || appController.groundingMode === modelData.mode ? "#342E43" : "transparent"
                    }
                }
            }
        }
    }

    IconButton {
        id: attach
        anchors.right: send.left
        anchors.bottom: parent.bottom
        anchors.rightMargin: 10
        anchors.bottomMargin: 12
        width: 52
        height: 52
        source: Qt.resolvedUrl("../../Icons/Paperclip_Attechment_Tilt.svg")
        tooltip: "Attach files"
        onClicked: filePicker.openAtHome()
    }

    IconButton {
        id: send
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: 12
        anchors.bottomMargin: 12
        width: 52
        height: 52
        source: Qt.resolvedUrl("../../Icons/Paper_Plane.svg")
        tooltip: "Send"
        onClicked: {
            appController.sendPrompt(input.text)
            input.text = ""
        }
    }
}
