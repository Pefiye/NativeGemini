import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts

Item {
    id: root
    width: 1280
    height: 720
    property bool overlayVisible: false
    property bool settingsOpen: false
    property bool chatroomsCollapsed: false
    readonly property int enterDuration: 380
    readonly property int exitDuration: 240

    function openEmptyChatroom() {
        settingsOpen = false
        appController.startNewChat()
        Qt.callLater(panel.focusComposer)
    }

    Shortcut {
        sequence: "Ctrl+T"
        enabled: root.overlayVisible
        onActivated: root.openEmptyChatroom()
    }

    Shortcut {
        sequence: "Ctrl+W"
        enabled: root.overlayVisible
        onActivated: root.openEmptyChatroom()
    }

    Rectangle {
        anchors.fill: parent
        color: "black"
        opacity: root.overlayVisible ? 0.25 : 0
        Behavior on opacity {
            NumberAnimation { duration: root.exitDuration; easing.type: Easing.OutCubic }
        }
    }

    ConversationList {
        id: conversations
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.margins: 18
        width: root.chatroomsCollapsed ? 66 : Math.min(parent.width * 0.34, 650)
        height: root.chatroomsCollapsed ? 66 : Math.min(parent.height * 0.36, 380)
        collapsed: root.chatroomsCollapsed
        onToggleCollapsed: root.chatroomsCollapsed = !root.chatroomsCollapsed
        onNewChatRequested: root.openEmptyChatroom()
        opacity: root.overlayVisible ? 1 : 0
        transform: Translate {
            x: root.overlayVisible ? 0 : -(conversations.width + 48)
            Behavior on x {
                NumberAnimation {
                    duration: root.overlayVisible ? root.enterDuration : root.exitDuration
                    easing.type: Easing.OutCubic
                }
            }
        }
        Behavior on opacity {
            NumberAnimation { duration: root.overlayVisible ? root.enterDuration : root.exitDuration }
        }
    }

    CharacterPortrait {
        id: portrait
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.leftMargin: parent.width * 0.19
        width: Math.min(parent.width * 0.36, 610)
        height: Math.min(parent.height * 0.58, 620)
        opacity: root.overlayVisible ? 1 : 0
        transform: Translate {
            y: root.overlayVisible ? 0 : portrait.height + 80
            Behavior on y {
                NumberAnimation {
                    duration: root.overlayVisible ? root.enterDuration + 80 : root.exitDuration
                    easing.type: Easing.OutCubic
                }
            }
        }
        Behavior on opacity {
            NumberAnimation { duration: root.overlayVisible ? root.enterDuration + 80 : root.exitDuration }
        }
    }

    ChatPanel {
        id: panel
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.margins: 18
        width: Math.min(parent.width * 0.34, 650)
        visible: root.overlayVisible || opacity > 0
        enabled: !root.settingsOpen
        opacity: root.overlayVisible && !root.settingsOpen ? 1 : 0
        z: 2
        transform: Translate {
            x: !root.overlayVisible ? panel.width + 64 : root.settingsOpen ? 18 : 0
            Behavior on x {
                NumberAnimation {
                    duration: root.overlayVisible ? 180 : root.exitDuration
                    easing.type: Easing.OutCubic
                }
            }
        }
        Behavior on opacity {
            NumberAnimation { duration: root.overlayVisible ? 150 : root.exitDuration }
        }
    }

    SettingsPage {
        id: settings
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.margins: 18
        width: Math.min(parent.width * 0.34, 650)
        visible: root.overlayVisible || opacity > 0
        enabled: root.settingsOpen
        onCloseRequested: root.settingsOpen = false
        opacity: root.overlayVisible && root.settingsOpen ? 1 : 0
        z: 3
        transform: Translate {
            x: !root.overlayVisible ? settings.width + 64 : root.settingsOpen ? 0 : 18
            Behavior on x {
                NumberAnimation {
                    duration: root.overlayVisible ? 180 : root.exitDuration
                    easing.type: Easing.OutCubic
                }
            }
        }
        Behavior on opacity {
            NumberAnimation { duration: root.overlayVisible ? 150 : root.exitDuration }
        }
    }

    Row {
        id: topControls
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 18
        spacing: 10
        visible: root.overlayVisible || opacity > 0
        enabled: !root.settingsOpen
        opacity: root.overlayVisible && !root.settingsOpen ? 1 : 0
        z: 4
        transform: Translate {
            x: !root.overlayVisible ? topControls.width + 64 : root.settingsOpen ? 18 : 0
            Behavior on x {
                NumberAnimation {
                    duration: root.overlayVisible ? 180 : root.exitDuration
                    easing.type: Easing.OutCubic
                }
            }
        }
        Behavior on opacity {
            NumberAnimation { duration: root.overlayVisible ? 150 : root.exitDuration }
        }

        IconButton {
            width: 56
            height: 56
            source: Qt.resolvedUrl("../../Icons/Settings.svg")
            tooltip: "Settings"
            onClicked: root.settingsOpen = true
        }

        IconButton {
            width: 56
            height: 56
            source: Qt.resolvedUrl("../../Icons/Arrows_Reload_01.svg")
            tooltip: "Refresh Gemini models"
            onClicked: appController.refreshModels()
        }

        DarkComboBox {
            id: modelPicker
            width: 340
            height: 56
            model: appController.models.length > 0 ? appController.models : [appController.selectedModel || "Save API key to load models"]
            currentIndex: Math.max(0, model.indexOf(appController.selectedModel))
            onActivated: appController.setSelectedModel(model[index])
        }
    }
}
