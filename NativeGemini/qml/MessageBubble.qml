import QtQuick
import QtQuick.Controls

Item {
    id: root
    property int messageId: 0
    property string role: "assistant"
    property string content: ""
    property string emotion: ""
    property bool canEdit: false
    property bool animateResponse: false
    property bool normalizeCompactMarkdown: true
    property real revealProgress: 1
    height: bubble.height + 4

    function startReveal() {
        revealAnimation.stop()
        if (role !== "assistant" || !animateResponse || content.length === 0) {
            revealProgress = 1
            return
        }
        revealProgress = 0
        revealAnimation.start()
    }

    function escapeHtml(value) {
        return String(value || "")
            .replace(/&/g, "&amp;")
            .replace(/</g, "&lt;")
            .replace(/>/g, "&gt;")
    }

    function repeatText(textValue, count) {
        var output = ""
        for (var i = 0; i < count; i++)
            output += textValue
        return output
    }

    function renderInlineText(value) {
        var safe = escapeHtml(value)
        safe = safe.replace(/\[([^\]]+)\]\((https?:\/\/[^)\s]+)\)/g, "<a href='$2' style='color: #E1DAFF;'>$1</a>")
        safe = safe.replace(/\*\*([^*]+)\*\*/g, "<b>$1</b>")
        safe = safe.replace(/(^|[^*])\*([^*\n]+?)\*(?=[^*]|$)/g, "$1<i>$2</i>")
        safe = safe.replace(/__([^_]+)__/g, "<b>$1</b>")
        safe = safe.replace(/(^|[^_])_([^_\n]+?)_(?=[^_]|$)/g, "$1<i>$2</i>")
        return safe
    }

    function renderInline(value) {
        var text = String(value || "")
        var html = ""
        var cursor = 0
        while (cursor < text.length) {
            var open = text.indexOf("`", cursor)
            if (open < 0) {
                html += renderInlineText(text.slice(cursor))
                break
            }
            html += renderInlineText(text.slice(cursor, open))
            var tickCount = 1
            while (open + tickCount < text.length && text.charAt(open + tickCount) === "`")
                tickCount++
            var marker = repeatText("`", tickCount)
            var contentStart = open + tickCount
            var close = text.indexOf(marker, contentStart)
            if (close < 0) {
                html += escapeHtml(marker)
                cursor = contentStart
                continue
            }
            html += "<code style='background-color: #171421; color: #F2EEFF; padding: 1px 5px;'>" + escapeHtml(text.slice(contentStart, close)) + "</code>"
            cursor = close + tickCount
        }
        return html
    }

    function normalizeMarkdown(value) {
        var normalized = value.replace(/\r\n/g, "\n")
        normalized = normalized.replace(/([^\n])\s+(#{1,3}\s+)/g, "$1\n\n$2")
        normalized = normalized.replace(/([^\n])\s+(-\s+(?:\*\*)?[A-Z0-9][^:\n]{1,72}:\s*)/g, "$1\n$2")
        normalized = normalized.replace(/([^\n])\s+(\d+\.\s+(?:\*\*)?[A-Z0-9][^:\n]{1,72}:\s*)/g, "$1\n$2")
        return normalized
    }

    function markdownLines(value) {
        var rawLines = value.split(/\n/)
        var lines = []
        for (var i = 0; i < rawLines.length; i++) {
            var line = rawLines[i]
            var trimmed = line.trim()
            if (/^#{1,6}$/.test(trimmed))
                continue
            if (/^\s{2,}\S/.test(line) && lines.length > 0 && /^(\s*[-*]\s+|\s*\d+\.\s+)/.test(lines[lines.length - 1])) {
                lines[lines.length - 1] += " " + trimmed
                continue
            }
            lines.push(line)
        }
        return lines
    }

    function parseTableRow(line) {
        var cleaned = line.trim()
        if (cleaned.charAt(0) === "|")
            cleaned = cleaned.slice(1)
        if (cleaned.charAt(cleaned.length - 1) === "|")
            cleaned = cleaned.slice(0, -1)
        var raw = cleaned.split("|")
        var cells = []
        for (var i = 0; i < raw.length; i++)
            cells.push(raw[i].trim())
        return cells
    }

    function isTableRow(line) {
        var trimmed = line.trim()
        return trimmed.indexOf("|") >= 0 && parseTableRow(trimmed).length > 1
    }

    function isTableSeparator(line) {
        if (!isTableRow(line))
            return false
        var cells = parseTableRow(line)
        for (var i = 0; i < cells.length; i++) {
            if (!/^:?-{3,}:?$/.test(cells[i].replace(/\s/g, "")))
                return false
        }
        return true
    }

    function renderTable(headers, rows) {
        var html = "<table cellspacing='0' cellpadding='6' style='margin: 8px 0 16px 0; border-collapse: collapse; background-color: #1B1726;'>"
        html += "<thead><tr>"
        for (var h = 0; h < headers.length; h++)
            html += "<th style='border: 1px solid #544B73; color: #F4F0FF; background-color: #2D263C; font-weight: 700;'>" + renderInline(headers[h]) + "</th>"
        html += "</tr></thead><tbody>"
        for (var r = 0; r < rows.length; r++) {
            html += "<tr>"
            for (var c = 0; c < headers.length; c++) {
                var cell = c < rows[r].length ? rows[r][c] : ""
                html += "<td style='border: 1px solid #41384F; color: #FFFFFF;'>" + renderInline(cell) + "</td>"
            }
            html += "</tr>"
        }
        html += "</tbody></table>"
        return html
    }

    function renderCodeBlock(lines, language) {
        var label = language ? "<div style='color: #BDB6D0; font-size: 12px; margin-bottom: 4px;'>" + escapeHtml(language) + "</div>" : ""
        return "<div style='margin: 8px 0 16px 0; padding: 10px; background-color: #171421; border: 1px solid #41384F;'>" + label + "<pre style='margin: 0; white-space: pre-wrap; color: #F5F2FF; font-family: monospace;'>" + escapeHtml(lines.join("\n")) + "</pre></div>"
    }

    function markdownToHtml(value) {
        var source = normalizeCompactMarkdown ? normalizeMarkdown(value) : value.replace(/\r\n/g, "\n")
        var lines = markdownLines(source)
        var html = ""
        var paragraph = []
        var inList = false
        var inOrderedList = false
        var inCodeBlock = false
        var codeFence = ""
        var codeLanguage = ""
        var codeLines = []

        function flushParagraph() {
            if (paragraph.length === 0)
                return
            html += "<p style='margin: 0 0 12px 0;'>" + paragraph.join(" ") + "</p>"
            paragraph = []
        }

        function closeList() {
            if (!inList)
                return
            html += inOrderedList ? "</ol>" : "</ul>"
            inList = false
            inOrderedList = false
        }

        for (var i = 0; i < lines.length; i++) {
            var line = lines[i]
            var trimmed = line.trim()
            var fence = trimmed.match(/^(```+|~~~+)\s*([^`]*)$/)
            var heading = trimmed.match(/^(#{1,3})\s+(.+)$/)
            var bullet = trimmed.match(/^[-*]\s+(.+)$/)
            var ordered = trimmed.match(/^\d+\.\s+(.+)$/)

            if (inCodeBlock) {
                if (fence && fence[1].charAt(0) === codeFence) {
                    html += renderCodeBlock(codeLines, codeLanguage)
                    inCodeBlock = false
                    codeFence = ""
                    codeLanguage = ""
                    codeLines = []
                } else {
                    codeLines.push(line)
                }
                continue
            }

            if (fence) {
                flushParagraph()
                closeList()
                inCodeBlock = true
                codeFence = fence[1].charAt(0)
                codeLanguage = fence[2].trim()
                codeLines = []
                continue
            }

            if (trimmed.length === 0) {
                flushParagraph()
                closeList()
                continue
            }

            if (isTableRow(trimmed) && i + 1 < lines.length && isTableSeparator(lines[i + 1])) {
                flushParagraph()
                closeList()
                var headers = parseTableRow(trimmed)
                var rows = []
                i += 2
                while (i < lines.length && isTableRow(lines[i].trim())) {
                    rows.push(parseTableRow(lines[i].trim()))
                    i++
                }
                i--
                html += renderTable(headers, rows)
                continue
            }

            if (heading) {
                flushParagraph()
                closeList()
                var size = heading[1].length === 1 ? 24 : heading[1].length === 2 ? 21 : 19
                html += "<h" + heading[1].length + " style='font-size: " + size + "px; line-height: 1.25; margin: 18px 0 8px 0;'>" + renderInline(heading[2]) + "</h" + heading[1].length + ">"
                continue
            }

            if (bullet || ordered) {
                flushParagraph()
                var orderedLine = ordered !== null
                if (!inList || inOrderedList !== orderedLine) {
                    closeList()
                    html += orderedLine ? "<ol style='margin: 6px 0 14px 24px; padding: 0;'>" : "<ul style='margin: 6px 0 14px 24px; padding: 0;'>"
                    inList = true
                    inOrderedList = orderedLine
                }
                html += "<li style='margin: 0 0 8px 0;'>" + renderInline(orderedLine ? ordered[1] : bullet[1]) + "</li>"
                continue
            }

            closeList()
            paragraph.push(renderInline(trimmed))
        }

        if (inCodeBlock)
            html += renderCodeBlock(codeLines, codeLanguage)
        flushParagraph()
        closeList()
        return "<div style='line-height: 1.35;'>" + html + "</div>"
    }

    Rectangle {
        id: bubble
        readonly property real maxBubbleWidth: parent.width * 0.86
        readonly property int horizontalPadding: 22
        readonly property int verticalPadding: 20
        width: Math.min(maxBubbleWidth, Math.max(280, Math.min(maxBubbleWidth, root.content.length * 8 + actions.width + horizontalPadding * 2 + 40)))
        height: Math.max(58, contentText.contentHeight + verticalPadding * 2)
        anchors.right: parent.right
        anchors.top: parent.top
        radius: 10
        color: root.role === "user" ? "#4A4268" : "#241F31"
        border.width: 0

        TextEdit {
            id: contentText
            anchors.left: parent.left
            anchors.right: actions.left
            anchors.top: parent.top
            anchors.leftMargin: bubble.horizontalPadding
            anchors.rightMargin: 14
            anchors.topMargin: bubble.verticalPadding
            anchors.bottomMargin: bubble.verticalPadding
            text: root.markdownToHtml(root.content)
            color: "white"
            font.pixelSize: 17
            wrapMode: Text.Wrap
            textFormat: TextEdit.RichText
            readOnly: true
            selectByMouse: true
            selectedTextColor: "white"
            selectionColor: "#544B73"

            TapHandler {
                acceptedButtons: Qt.LeftButton
                onTapped: function(eventPoint, button) {
                    var link = contentText.linkAt(eventPoint.position.x, eventPoint.position.y)
                    if (link)
                        Qt.openUrlExternally(link)
                }
            }
        }

        Rectangle {
            anchors.left: contentText.left
            anchors.right: contentText.right
            anchors.bottom: contentText.bottom
            height: Math.max(0, contentText.contentHeight * (1 - root.revealProgress))
            color: bubble.color
            visible: root.revealProgress < 1
            z: 2
        }

        Rectangle {
            id: actions
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: 8
            width: actionRow.implicitWidth + 8
            height: 38
            radius: 8
            color: root.canEdit ? "#332D43" : "transparent"
            border.color: root.canEdit ? "#484057" : "transparent"
            border.width: root.canEdit ? 1 : 0
            opacity: root.role === "user" ? 0.96 : 0.82

            Behavior on opacity {
                NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
            }

            Row {
                id: actionRow
                anchors.centerIn: parent
                spacing: 4

                IconButton {
                    width: 30
                    height: 30
                    source: Qt.resolvedUrl("../../Icons/Copy.svg")
                    tooltip: "Copy message"
                    onClicked: appController.copyMessageText(root.content)
                }

                IconButton {
                    id: editButton
                    visible: root.canEdit
                    width: 30
                    height: 30
                    source: Qt.resolvedUrl("../../Icons/Edit_Pencil_Line_01.svg")
                    tooltip: "Edit last prompt"
                    onClicked: editDialog.openWith(root.content)
                }
            }
        }
    }

    Dialog {
        id: editDialog
        parent: Overlay.overlay
        modal: true
        dim: true
        padding: 0
        width: Math.min(560, Math.max(360, parent ? parent.width - 48 : 560))
        x: parent ? Math.round((parent.width - width) / 2) : 0
        y: parent ? Math.round((parent.height - height) / 2) : 0
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

        Overlay.modal: Rectangle {
            color: "#660C0A12"
        }

        function openWith(textValue) {
            editor.text = textValue
            open()
            editor.forceActiveFocus()
            editor.cursorPosition = editor.text.length
        }

        background: Rectangle {
            radius: 12
            color: "#F0211D31"
            border.color: "#5B5270"
            border.width: 1
        }

        contentItem: Rectangle {
            implicitWidth: editDialog.width
            implicitHeight: 308
            radius: 12
            color: "transparent"

            Column {
                anchors.fill: parent
                anchors.margins: 18
                spacing: 14

                Row {
                    width: parent.width
                    height: 42
                    spacing: 12

                    IconButton {
                        width: 42
                        height: 42
                        enabled: false
                        opacity: 1
                        source: Qt.resolvedUrl("../../Icons/Edit_Pencil_Line_01.svg")
                    }

                    Column {
                        width: parent.width - 54
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2

                        Text {
                            width: parent.width
                            text: "Edit Last Prompt"
                            color: "white"
                            font.pixelSize: 20
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }

                        Text {
                            width: parent.width
                            text: "Update the message and resend it."
                            color: "#CFC9DF"
                            font.pixelSize: 13
                            elide: Text.ElideRight
                        }
                    }
                }

                ScrollView {
                    id: editScroll
                    width: parent.width
                    height: 156
                    clip: true
                    ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                    ScrollBar.vertical.policy: editor.contentHeight > height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff

                    TextArea {
                        id: editor
                        width: editScroll.availableWidth
                        height: Math.max(editScroll.height, contentHeight)
                        wrapMode: TextArea.Wrap
                        selectByMouse: true
                        color: "white"
                        selectedTextColor: "white"
                        selectionColor: "#544B73"
                        placeholderText: "Edit your prompt"
                        placeholderTextColor: "#AFA7C4"
                        font.pixelSize: 17
                        background: Rectangle {
                            radius: 9
                            color: "#241F31"
                            border.color: editor.activeFocus ? "#756A92" : "#41384F"
                            border.width: 1
                        }
                        Keys.onPressed: function(event) {
                            if ((event.modifiers & Qt.ControlModifier) && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)) {
                                editDialog.accept()
                                event.accepted = true
                            }
                        }
                    }
                }

                Row {
                    width: parent.width
                    height: 44
                    spacing: 10

                    Item {
                        width: parent.width - cancelButton.width - saveButton.width - parent.spacing * 2
                        height: 1
                    }

                    DarkButton {
                        id: cancelButton
                        width: 110
                        height: 44
                        text: "Cancel"
                        icon.source: Qt.resolvedUrl("../../Icons/Close_SM.svg")
                        onClicked: editDialog.reject()
                    }

                    DarkButton {
                        id: saveButton
                        width: 128
                        height: 44
                        text: "Resend"
                        icon.source: Qt.resolvedUrl("../../Icons/Check.svg")
                        enabled: editor.text.trim().length > 0
                        onClicked: editDialog.accept()
                    }
                }
            }
        }

        onAccepted: appController.editLastPrompt(editor.text)

        enter: Transition {
            ParallelAnimation {
                NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 140; easing.type: Easing.OutCubic }
                NumberAnimation { property: "scale"; from: 0.97; to: 1; duration: 160; easing.type: Easing.OutCubic }
            }
        }

        exit: Transition {
            ParallelAnimation {
                NumberAnimation { property: "opacity"; from: 1; to: 0; duration: 100; easing.type: Easing.InCubic }
                NumberAnimation { property: "scale"; from: 1; to: 0.98; duration: 110; easing.type: Easing.InCubic }
            }
        }
    }

    NumberAnimation {
        id: revealAnimation
        target: root
        property: "revealProgress"
        from: 0
        to: 1
        duration: 420
        easing.type: Easing.OutCubic
        onFinished: {
            root.revealProgress = 1
            appController.markMessageAnimationDone(root.messageId)
        }
    }

    Component.onCompleted: startReveal()
    onContentChanged: startReveal()
    onAnimateResponseChanged: startReveal()
}
