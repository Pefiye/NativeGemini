import QtQuick
import QtQuick.Controls
import QtQuick.Controls.impl

Rectangle {
    id: root
    property bool collapsed: false
    signal toggleCollapsed()
    signal newChatRequested()
    color: "#CC211D31"
    radius: 10
    border.color: "#41384F"
    border.width: 1
    clip: true

    Behavior on width {
        NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
    }

    Behavior on height {
        NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
    }

    IconButton {
        id: expandButton
        anchors.centerIn: parent
        width: 42
        height: 42
        visible: root.collapsed
        source: Qt.resolvedUrl("../../Icons/Chevron_Right.svg")
        tooltip: "Expand chatrooms"
        onClicked: root.toggleCollapsed()
    }

    Column {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 10
        visible: !root.collapsed

        Row {
            id: header
            width: parent.width
            height: 42
            spacing: 8

            Text {
                width: parent.width - collapseButton.width - newChatButton.width - parent.spacing * 2
                anchors.verticalCenter: parent.verticalCenter
                text: "Chatrooms"
                color: "white"
                font.pixelSize: 20
                font.bold: true
                elide: Text.ElideRight
            }

            IconButton {
                id: collapseButton
                width: 42
                height: 42
                source: Qt.resolvedUrl("../../Icons/Chevron_Left.svg")
                tooltip: "Collapse chatrooms"
                onClicked: root.toggleCollapsed()
            }

            IconButton {
                id: newChatButton
                width: 42
                height: 42
                source: Qt.resolvedUrl("../../Icons/Chat_Add.svg")
                tooltip: "Start new chat"
                onClicked: {
                    searchInput.text = ""
                    root.newChatRequested()
                }
            }
        }

        TextField {
            id: searchInput
            width: parent.width
            height: 42
            text: appController.conversationSearch
            placeholderText: "Search chats"
            placeholderTextColor: "#BFB8D8"
            color: "white"
            selectedTextColor: "white"
            selectionColor: "#544B73"
            font.pixelSize: 16
            leftPadding: 14
            rightPadding: 14
            selectByMouse: true
            onTextChanged: appController.setConversationSearch(text)

            background: Rectangle {
                radius: 8
                color: "#241F31"
                border.color: searchInput.activeFocus ? "#6A5E82" : "#41384F"
                border.width: 1
            }
        }

        ListView {
            id: chatList
            width: parent.width
            height: parent.height - header.height - searchInput.height - parent.spacing * 2
            clip: true
            spacing: 4
            boundsBehavior: Flickable.StopAtBounds
            model: appController.conversations.length > 0 ? appController.conversations : [
                {"id": 0, "title": appController.conversationSearch.length > 0 ? "No matching chats" : "No conversations yet"}
            ]
            delegate: Rectangle {
                width: ListView.view.width
                height: 46
                radius: 7
                readonly property bool isRealConversation: modelData.id > 0
                readonly property bool isSelected: modelData.id === appController.currentConversationId
                color: isSelected ? "#342E43" : rowMouse.containsMouse ? "#2A2536" : "transparent"

                Behavior on color {
                    ColorAnimation { duration: 120; easing.type: Easing.OutCubic }
                }

                MouseArea {
                    id: rowMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: parent.isRealConversation ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: if (parent.isRealConversation) appController.selectConversation(modelData.id)
                }

                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 8
                    anchors.right: parent.isSelected ? actions.left : parent.right
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData.title
                    color: parent.isRealConversation ? "white" : "#BFB8D8"
                    font.pixelSize: 17
                    elide: Text.ElideRight
                    z: 1
                }

                Row {
                    id: actions
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 4
                    visible: parent.isRealConversation && parent.isSelected
                    z: 2

                    IconButton {
                        width: 34
                        height: 32
                        source: Qt.resolvedUrl("../../Icons/Edit_Pencil_01.svg")
                        tooltip: "Rename"
                        onClicked: renamePopup.openFor(modelData.id, modelData.title)
                    }

                    IconButton {
                        width: 34
                        height: 32
                        source: Qt.resolvedUrl("../../Icons/Trash_Empty.svg")
                        tooltip: "Delete"
                        onClicked: deletePopup.openFor(modelData.id, modelData.title)
                    }
                }
            }
        }
    }

    Popup {
        id: deletePopup
        parent: Overlay.overlay
        width: 340
        height: 174
        x: parent ? Math.round((parent.width - width) / 2) : 0
        y: parent ? Math.round((parent.height - height) / 2) : 0
        modal: true
        focus: true
        padding: 16
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        property int conversationId: 0
        property string conversationTitle: ""

        function openFor(id, titleText) {
            conversationId = id
            conversationTitle = titleText
            open()
        }

        background: Rectangle {
            radius: 10
            color: "#211D31"
            border.color: "#5B5270"
            border.width: 1
        }

        contentItem: Column {
            spacing: 12

            Row {
                width: parent.width
                height: 38
                spacing: 10

                ColorImage {
                    width: 28
                    height: 28
                    anchors.verticalCenter: parent.verticalCenter
                    source: Qt.resolvedUrl("../../Icons/Trash_Empty.svg")
                    color: "white"
                    sourceSize.width: 24
                    sourceSize.height: 24
                    fillMode: Image.PreserveAspectFit
                }

                Text {
                    width: parent.width - 38
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Delete chatroom?"
                    color: "white"
                    font.pixelSize: 18
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }
            }

            Text {
                width: parent.width
                text: deletePopup.conversationTitle
                color: "#DCD8EA"
                font.pixelSize: 14
                elide: Text.ElideRight
            }

            Row {
                width: parent.width
                height: 42
                spacing: 8

                DarkButton {
                    width: (parent.width - parent.spacing) / 2
                    height: parent.height
                    text: "Cancel"
                    onClicked: deletePopup.close()
                }

                DarkButton {
                    width: (parent.width - parent.spacing) / 2
                    height: parent.height
                    text: "Delete"
                    icon.source: Qt.resolvedUrl("../../Icons/Trash_Empty.svg")
                    onClicked: {
                        appController.deleteConversation(deletePopup.conversationId)
                        deletePopup.close()
                    }
                }
            }
        }
    }

    Popup {
        id: renamePopup
        parent: Overlay.overlay
        width: 330
        height: 158
        x: parent ? Math.round((parent.width - width) / 2) : 0
        y: parent ? Math.round((parent.height - height) / 2) : 0
        modal: true
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        property int conversationId: 0

        function openFor(id, titleText) {
            conversationId = id
            titleInput.text = titleText
            open()
            titleInput.forceActiveFocus()
            titleInput.selectAll()
        }

        background: Rectangle {
            radius: 10
            color: "#211D31"
            border.color: "#41384F"
            border.width: 1
        }

        contentItem: Column {
            spacing: 12

            Text {
                width: parent.width
                text: "Rename chat"
                color: "white"
                font.pixelSize: 18
                font.bold: true
            }

            TextField {
                id: titleInput
                width: parent.width
                height: 42
                color: "white"
                selectedTextColor: "white"
                selectionColor: "#544B73"
                font.pixelSize: 16
                selectByMouse: true
                Keys.onReturnPressed: renamePopup.save()
                Keys.onEnterPressed: renamePopup.save()

                background: Rectangle {
                    radius: 8
                    color: "#171421"
                    border.color: titleInput.activeFocus ? "#6A5E82" : "#41384F"
                    border.width: 1
                }
            }

            Row {
                width: parent.width
                height: 38
                spacing: 8

                DarkButton {
                    width: (parent.width - parent.spacing) / 2
                    height: parent.height
                    text: "Cancel"
                    onClicked: renamePopup.close()
                }

                DarkButton {
                    width: (parent.width - parent.spacing) / 2
                    height: parent.height
                    text: "Save"
                    icon.source: Qt.resolvedUrl("../../Icons/Check.svg")
                    onClicked: renamePopup.save()
                }
            }
        }

        function save() {
            appController.renameConversation(conversationId, titleInput.text)
            close()
        }
    }
}
