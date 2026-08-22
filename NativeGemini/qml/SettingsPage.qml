import QtQuick
import QtQuick.Controls

Rectangle {
    id: root
    signal closeRequested()
    radius: 10
    color: "#E0211D31"
    border.color: "#41384F"
    border.width: 1
    clip: true

    function usage(name) {
        var summary = appController.usageSummary
        return summary && summary[name] ? summary[name] : 0
    }

    function formatCount(value) {
        return Number(value || 0).toLocaleString(Qt.locale(), "f", 0)
    }

    AppFilePicker {
        id: folderPicker
        title: "Select Character Folder"
        folderMode: true
        onFolderAccepted: function(url) {
            appController.loadCharacterFolder(url)
        }
    }

    component UsageCard: Rectangle {
        property string label: ""
        property string value: ""
        property string detail: ""

        height: 100
        radius: 8
        color: "#241F31"
        border.color: "#41384F"
        border.width: 1
        clip: true

        Column {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 5

            Text {
                width: parent.width
                text: label
                color: "#BDB6D0"
                font.pixelSize: 12
                elide: Text.ElideRight
                maximumLineCount: 1
            }

            Text {
                width: parent.width
                text: value
                color: "white"
                font.pixelSize: 21
                font.weight: Font.DemiBold
                elide: Text.ElideRight
                maximumLineCount: 1
            }

            Text {
                width: parent.width
                visible: detail.length > 0
                text: detail
                color: "#DCD8EA"
                font.pixelSize: 12
                elide: Text.ElideRight
                maximumLineCount: 1
            }
        }
    }

    ScrollView {
        id: settingsScroll
        anchors.fill: parent
        anchors.margins: 24
        clip: true
        contentWidth: availableWidth
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

        Column {
            width: settingsScroll.availableWidth
            spacing: 18

            Row {
                width: parent.width
                height: 64
                spacing: 10

                IconButton {
                    width: 64
                    height: 64
                    source: Qt.resolvedUrl("../../Icons/Chevron_Left.svg")
                    tooltip: "Back"
                    onClicked: root.closeRequested()
                }

                Rectangle {
                    width: parent.width - 74
                    height: 64
                    radius: 8
                    color: "#241F31"

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.leftMargin: 20
                        text: "Settings"
                        color: "white"
                        font.pixelSize: 24
                        font.weight: Font.DemiBold
                    }
                }
            }

            Text {
                text: "API Keys"
                color: "white"
                font.pixelSize: 18
            }

            Row {
                width: parent.width
                height: 64
                spacing: 10

                TextField {
                    id: apiKey
                    width: parent.width - 150
                    height: 64
                    echoMode: TextInput.Password
                    placeholderText: appController.apiKeySaved ? "API key saved securely" : "Gemini API key"
                    color: "white"
                    font.pixelSize: 18
                    background: Rectangle {
                        radius: 8
                        color: "#241F31"
                        border.color: apiKey.activeFocus ? "#6A5E82" : "#41384F"
                        border.width: 1
                    }
                }

                DarkButton {
                    width: 140
                    height: 64
                    text: "Save"
                    onClicked: appController.saveApiKey(apiKey.text)
                }
            }

            Text {
                width: parent.width
                text: appController.apiKeySaved ? "A Gemini API key is stored in the system wallet. Enter a new key only if you want to replace it." : "No Gemini API key is stored yet."
                color: "#DCD8EA"
                font.pixelSize: 14
                wrapMode: Text.Wrap
            }

            Row {
                width: parent.width
                height: 64
                spacing: 10

                TextField {
                    id: tavilyApiKey
                    width: parent.width - 150
                    height: 64
                    echoMode: TextInput.Password
                    placeholderText: appController.tavilyApiKeySaved ? "Tavily API key saved securely" : "Tavily API key"
                    color: "white"
                    font.pixelSize: 18
                    background: Rectangle {
                        radius: 8
                        color: "#241F31"
                        border.color: tavilyApiKey.activeFocus ? "#6A5E82" : "#41384F"
                        border.width: 1
                    }
                }

                DarkButton {
                    width: 140
                    height: 64
                    text: "Save"
                    onClicked: appController.saveTavilyApiKey(tavilyApiKey.text)
                }
            }

            Text {
                width: parent.width
                text: appController.tavilyApiKeySaved ? "A Tavily API key is stored in the system wallet for web grounding." : "No Tavily API key is stored yet. Web grounding falls back to Gemini's native grounding only."
                color: "#DCD8EA"
                font.pixelSize: 14
                wrapMode: Text.Wrap
            }

            Text {
                text: "Local Usage"
                color: "white"
                font.pixelSize: 18
            }

            Flow {
                width: parent.width
                spacing: 10

                UsageCard {
                    width: Math.max(150, (parent.width - 10) / 2)
                    label: "Today"
                    value: root.formatCount(root.usage("todayRequests")) + " requests"
                    detail: root.formatCount(root.usage("todayTotalTokens")) + " est. tokens"
                }

                UsageCard {
                    width: Math.max(150, (parent.width - 10) / 2)
                    label: "Last 24 Hours"
                    value: root.formatCount(root.usage("dayRequests")) + " requests"
                    detail: root.formatCount(root.usage("dayTotalTokens")) + " est. tokens"
                }

                UsageCard {
                    width: Math.max(150, (parent.width - 10) / 2)
                    label: "Last 7 Days"
                    value: root.formatCount(root.usage("weekRequests")) + " requests"
                    detail: root.formatCount(root.usage("weekTotalTokens")) + " est. tokens"
                }

                UsageCard {
                    width: Math.max(150, (parent.width - 10) / 2)
                    label: "Grounding"
                    value: root.formatCount(root.usage("weekGrounded")) + " attempts"
                    detail: root.formatCount(root.usage("weekTavilySearches")) + " Tavily searches"
                }
            }

            Row {
                width: parent.width
                height: 46
                spacing: 10

                DarkButton {
                    width: (parent.width - 10) / 2
                    height: 46
                    text: "AI Studio Usage"
                    onClicked: Qt.openUrlExternally("https://aistudio.google.com/usage?timeRange=last-28-days&tab=usage")
                }

                DarkButton {
                    width: (parent.width - 10) / 2
                    height: 46
                    text: "Rate Limits"
                    onClicked: Qt.openUrlExternally("https://aistudio.google.com/usage?timeRange=last-28-days&tab=rate-limit")
                }
            }

            Text {
                width: parent.width
                text: "Local estimates only. AI Studio remains the source of truth for billing and quota."
                color: "#BDB6D0"
                font.pixelSize: 13
                wrapMode: Text.Wrap
            }

            Text {
                text: "Character"
                color: "white"
                font.pixelSize: 18
            }

            Row {
                width: parent.width
                height: 72
                spacing: 10

                Rectangle {
                    width: parent.width - 190
                    height: 72
                    radius: 8
                    color: "#241F31"
                    border.color: "#41384F"
                    border.width: 1

                    Image {
                        id: icon
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: 14
                        width: 48
                        height: 48
                        source: appController.characterIconUrl
                        fillMode: Image.PreserveAspectFit
                    }

                    Text {
                        anchors.left: icon.right
                        anchors.leftMargin: 14
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.right: parent.right
                        anchors.rightMargin: 12
                        text: appController.characterName
                        color: "white"
                        font.pixelSize: 20
                        elide: Text.ElideRight
                    }
                }

                DarkButton {
                    width: 180
                    height: 72
                    text: "Select Folder"
                    onClicked: folderPicker.openAtHome()
                }
            }

            Flow {
                width: parent.width
                spacing: 10

                Repeater {
                    model: appController.emotions
                    delegate: Rectangle {
                        width: Math.max(132, emotionText.implicitWidth + 34)
                        height: 38
                        radius: 8
                        color: "#241F31"
                        border.color: "#41384F"
                        border.width: 1

                        Text {
                            id: emotionText
                            anchors.centerIn: parent
                            text: modelData
                            color: "white"
                            font.pixelSize: 17
                        }
                    }
                }
            }
        }
    }
}
