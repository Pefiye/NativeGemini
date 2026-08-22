import QtQuick
import QtQuick.Controls

Item {
    id: root
    property int bottomScrollPasses: 0
    property bool bottomScrollForced: false
    property bool pendingConversationBottom: false

    function focusComposer() {
        inputBar.focusComposer()
    }

    function isNearBottom() {
        if (messageList.contentHeight <= messageList.height)
            return true
        return messageList.contentY + messageList.height >= messageList.contentHeight - 96
    }

    function isUserScrolling() {
        return messageList.moving || messageList.flicking || chatScrollBar.pressed
    }

    function scheduleBottomScroll(passes, force) {
        if (!force && isUserScrolling())
            return
        bottomScrollPasses = Math.max(bottomScrollPasses, passes || 1)
        bottomScrollForced = bottomScrollForced || !!force
        bottomScrollTimer.restart()
    }

    function scrollMessagesToBottom() {
        scheduleBottomScroll(2, true)
    }

    Column {
        anchors.fill: parent
        spacing: 10
        topPadding: 88

        Item {
            id: messageViewport
            objectName: "messageViewport"
            width: parent.width
            height: Math.max(0, parent.height - inputBar.height - 108)

            Flickable {
                id: messageList
                objectName: "messageList"
                anchors.fill: parent
                clip: true
                opacity: 1
                transform: Translate { id: messageListShift }
                contentWidth: width
                contentHeight: messageColumn.implicitHeight
                boundsBehavior: Flickable.StopAtBounds
                flickableDirection: Flickable.VerticalFlick
                pixelAligned: true
                maximumFlickVelocity: 5400
                flickDeceleration: 4200
                onContentHeightChanged: {
                    if (root.pendingConversationBottom || root.isNearBottom())
                        root.scheduleBottomScroll(2, root.pendingConversationBottom)
                }

                ScrollBar.vertical: ScrollBar {
                    id: chatScrollBar
                    policy: messageList.contentHeight > messageList.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
                }

                Column {
                    id: messageColumn
                    width: messageList.width
                    spacing: 12

                    Repeater {
                        model: appController.messages

                        delegate: MessageBubble {
                            width: messageColumn.width
                            messageId: modelData.id
                            role: modelData.role
                            content: modelData.content
                            emotion: modelData.emotion
                            canEdit: modelData.canEdit
                            animateResponse: modelData.animate
                        }
                    }

                    Item {
                        id: activityIndicator
                        width: messageColumn.width
                        height: appController.activityMode.length > 0 ? 48 : 0
                        visible: height > 0
                        clip: true

                        Rectangle {
                            id: activityBubble
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.topMargin: 4
                            width: Math.min(parent.width * 0.86, activityRow.implicitWidth + 28)
                            height: 38
                            radius: 10
                            color: "#241F31"
                            clip: true

                            Row {
                                id: activityRow
                                anchors.centerIn: parent
                                height: Math.max(searchLabel.implicitHeight, 14)
                                spacing: 8

                                Text {
                                    id: searchLabel
                                    visible: appController.activityMode === "searching"
                                    text: "Searching the web"
                                    color: "white"
                                    font.pixelSize: 15
                                }

                                Repeater {
                                    model: 3

                                    delegate: Item {
                                        width: 7
                                        height: activityRow.height

                                        Rectangle {
                                            anchors.centerIn: parent
                                            width: 7
                                            height: 7
                                            radius: 4
                                            color: "#CFC9DF"
                                            opacity: 0.35

                                            SequentialAnimation on opacity {
                                                loops: Animation.Infinite
                                                running: activityIndicator.visible
                                                PauseAnimation { duration: index * 140 }
                                                NumberAnimation { to: 1.0; duration: 280; easing.type: Easing.OutCubic }
                                                NumberAnimation { to: 0.35; duration: 360; easing.type: Easing.InCubic }
                                                PauseAnimation { duration: 220 }
                                            }

                                            SequentialAnimation on scale {
                                                loops: Animation.Infinite
                                                running: activityIndicator.visible
                                                PauseAnimation { duration: index * 140 }
                                                NumberAnimation { to: 1.22; duration: 280; easing.type: Easing.OutCubic }
                                                NumberAnimation { to: 1.0; duration: 360; easing.type: Easing.InCubic }
                                                PauseAnimation { duration: 220 }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                Connections {
                    target: appController

                    function onActivityModeChanged() {
                        if (root.isNearBottom())
                            root.scheduleBottomScroll(1, false)
                    }

                    function onCurrentConversationChanged() {
                        root.pendingConversationBottom = true
                        chatSwitchAnimation.restart()
                        root.scheduleBottomScroll(4, true)
                    }

                    function onMessagesChanged() {
                        if (root.pendingConversationBottom || root.isNearBottom())
                            root.scheduleBottomScroll(3, root.pendingConversationBottom)
                    }
                }

                Timer {
                    id: bottomScrollTimer
                    interval: 1
                    repeat: false

                    onTriggered: {
                        if (!root.bottomScrollForced && root.isUserScrolling()) {
                            root.bottomScrollPasses = 0
                            return
                        }
                        messageList.contentY = Math.max(0, messageList.contentHeight - messageList.height)
                        messageList.returnToBounds()
                        root.pendingConversationBottom = false
                        root.bottomScrollPasses -= 1
                        if (root.bottomScrollPasses > 0) {
                            restart()
                        } else {
                            root.bottomScrollForced = false
                        }
                    }
                }

                SequentialAnimation {
                    id: chatSwitchAnimation

                    PropertyAction { target: messageList; property: "opacity"; value: 0.55 }
                    PropertyAction { target: messageListShift; property: "x"; value: 14 }

                    ParallelAnimation {
                        NumberAnimation {
                            target: messageList
                            property: "opacity"
                            to: 1
                            duration: 150
                            easing.type: Easing.OutCubic
                        }
                        NumberAnimation {
                            target: messageListShift
                            property: "x"
                            to: 0
                            duration: 170
                            easing.type: Easing.OutCubic
                        }
                    }
                }
            }

        }

        InputBar {
            id: inputBar
            width: parent.width
        }
    }
}
