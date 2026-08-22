import QtQuick
import QtQuick.Controls
import Qt.labs.folderlistmodel

Popup {
    id: root
    parent: Overlay.overlay
    property bool folderMode: false
    property string title: folderMode ? "Select Folder" : "Attach Files"
    property var nameFilters: ["*"]
    property url currentFolder: appController.homeUrl
    property var selectedUrls: []
    signal filesAccepted(var urls)
    signal folderAccepted(string url)

    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    width: Math.min(parent ? parent.width - 48 : 760, 760)
    height: Math.min(parent ? parent.height - 48 : 560, 560)
    x: parent ? Math.round((parent.width - width) / 2) : 0
    y: parent ? Math.round((parent.height - height) / 2) : 0
    padding: 0

    function openAtHome() {
        selectedUrls = []
        currentFolder = appController.homeUrl
        open()
    }

    function asText(value) {
        return String(value || "")
    }

    function pathText(urlValue) {
        var text = decodeURIComponent(asText(urlValue).replace(/^file:\/\//, ""))
        return text.length > 1 ? text : "/"
    }

    function parentFolder(urlValue) {
        var path = pathText(urlValue)
        if (path === "/")
            return "file:///"
        path = path.replace(/\/+$/, "")
        var slash = path.lastIndexOf("/")
        return encodeURI("file://" + (slash <= 0 ? "/" : path.slice(0, slash)))
    }

    function isSelected(urlValue) {
        var text = asText(urlValue)
        for (var i = 0; i < selectedUrls.length; i++) {
            if (selectedUrls[i] === text)
                return true
        }
        return false
    }

    function toggleSelected(urlValue) {
        var text = asText(urlValue)
        var next = selectedUrls.slice()
        var index = next.indexOf(text)
        if (index >= 0)
            next.splice(index, 1)
        else if (folderMode)
            next = [text]
        else
            next.push(text)
        selectedUrls = next
    }

    function acceptSelection() {
        if (folderMode) {
            folderAccepted(selectedUrls.length > 0 ? selectedUrls[0] : asText(currentFolder))
        } else if (selectedUrls.length > 0) {
            filesAccepted(selectedUrls)
        }
        close()
    }

    function isImageName(name) {
        return /\.(png|jpe?g|webp|gif|bmp|svg|heic|heif)$/i.test(String(name || ""))
    }

    Overlay.modal: Rectangle {
        color: "#660C0A12"
    }

    background: Rectangle {
        radius: 12
        color: "#F0211D31"
        border.color: "#514761"
        border.width: 1
    }

    FolderListModel {
        id: folderModel
        folder: root.currentFolder
        nameFilters: root.folderMode ? ["*"] : root.nameFilters
        showDirs: true
        showFiles: !root.folderMode
        showDirsFirst: true
        showDotAndDotDot: false
        sortField: FolderListModel.Name
    }

    contentItem: Column {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 12

        Row {
            width: parent.width
            height: 42
            spacing: 10

            Text {
                width: parent.width - closeButton.width - parent.spacing
                anchors.verticalCenter: parent.verticalCenter
                text: root.title
                color: "white"
                font.pixelSize: 20
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }

            IconButton {
                id: closeButton
                width: 42
                height: 42
                source: Qt.resolvedUrl("../../Icons/Close_SM.svg")
                tooltip: "Close"
                onClicked: root.close()
            }
        }

        Rectangle {
            width: parent.width
            height: 48
            radius: 8
            color: "#241F31"
            border.color: "#41384F"
            border.width: 1

            IconButton {
                id: upButton
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: 6
                width: 36
                height: 36
                source: Qt.resolvedUrl("../../Icons/Chevron_Left.svg")
                rotation: 90
                tooltip: "Up"
                onClicked: root.currentFolder = root.parentFolder(root.currentFolder)
            }

            Text {
                anchors.left: upButton.right
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: 10
                anchors.rightMargin: 14
                text: root.pathText(root.currentFolder)
                color: "#E7E1F7"
                font.pixelSize: 15
                elide: Text.ElideLeft
            }
        }

        GridView {
            id: fileGrid
            width: parent.width
            height: parent.height - 42 - 48 - footer.height - parent.spacing * 3
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: folderModel
            cellWidth: Math.max(126, Math.floor(width / Math.max(1, Math.floor(width / 136))))
            cellHeight: 148

            delegate: Rectangle {
                width: fileGrid.cellWidth - 10
                height: fileGrid.cellHeight - 10
                radius: 8
                readonly property bool selected: root.isSelected(fileUrl)
                readonly property bool previewable: root.isImageName(fileName)
                color: selected ? "#4A4268" : tileMouse.containsMouse ? "#342E43" : "#1B1726"
                border.color: selected ? "#8578A8" : tileMouse.containsMouse ? "#5D5271" : "#332D43"
                border.width: selected || tileMouse.containsMouse ? 1 : 0

                Behavior on color {
                    ColorAnimation { duration: 100; easing.type: Easing.OutCubic }
                }

                MouseArea {
                    id: tileMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (root.folderMode || !fileIsDir)
                            root.toggleSelected(fileUrl)
                    }
                    onDoubleClicked: {
                        if (fileIsDir) {
                            root.currentFolder = fileUrl
                            root.selectedUrls = []
                        } else {
                            root.selectedUrls = [String(fileUrl)]
                            root.acceptSelection()
                        }
                    }
                }

                Rectangle {
                    id: thumbnailFrame
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 8
                    height: 78
                    radius: 7
                    color: "#241F31"
                    border.color: "#41384F"
                    border.width: 1
                    clip: true

                    Image {
                        anchors.fill: parent
                        anchors.margins: 1
                        visible: !fileIsDir && parent.parent.previewable
                        source: fileUrl
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        cache: true
                    }

                    Button {
                        anchors.centerIn: parent
                        width: 38
                        height: 38
                        visible: fileIsDir || !thumbnailFrame.parent.previewable
                        enabled: false
                        opacity: 1
                        text: ""
                        icon.source: fileIsDir
                            ? Qt.resolvedUrl("../../Icons/Folder.svg")
                            : Qt.resolvedUrl("../../Icons/File_Document.svg")
                        icon.color: "white"
                        icon.width: 34
                        icon.height: 34
                        background: Item {}
                    }
                }

                Column {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: thumbnailFrame.bottom
                    anchors.bottom: parent.bottom
                    anchors.margins: 8
                    anchors.topMargin: 7
                    spacing: 2

                    Text {
                        width: parent.width
                        text: fileName
                        color: "white"
                        font.pixelSize: 13
                        elide: Text.ElideRight
                        maximumLineCount: 2
                        wrapMode: Text.Wrap
                    }

                    Text {
                        visible: !fileIsDir
                        width: parent.width
                        text: Math.max(1, Math.ceil(fileSize / 1024)) + " KB"
                        color: "#BDB5D2"
                        font.pixelSize: 11
                        elide: Text.ElideRight
                    }
                }

                Rectangle {
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 8
                    width: 22
                    height: 22
                    radius: 11
                    visible: parent.selected
                    color: "#4A4268"
                    border.color: "#8578A8"
                    border.width: 1

                    Button {
                        anchors.centerIn: parent
                        width: 14
                        height: 14
                        enabled: false
                        opacity: 1
                        text: ""
                        icon.source: Qt.resolvedUrl("../../Icons/Check.svg")
                        icon.color: "white"
                        icon.width: 13
                        icon.height: 13
                        background: Item {}
                    }
                }
            }
        }

        Row {
            id: footer
            width: parent.width
            height: 44
            spacing: 10

            Text {
                width: parent.width - cancelButton.width - openButton.width - parent.spacing * 2
                anchors.verticalCenter: parent.verticalCenter
                text: root.folderMode
                    ? (root.selectedUrls.length > 0 ? "Selected folder" : "Current folder will be used")
                    : (root.selectedUrls.length + " selected")
                color: "#CFC9DF"
                font.pixelSize: 13
                elide: Text.ElideRight
            }

            DarkButton {
                id: cancelButton
                width: 110
                height: 44
                text: "Cancel"
                onClicked: root.close()
            }

            DarkButton {
                id: openButton
                width: 120
                height: 44
                text: root.folderMode ? "Select" : "Attach"
                enabled: root.folderMode || root.selectedUrls.length > 0
                onClicked: root.acceptSelection()
            }
        }
    }
}
