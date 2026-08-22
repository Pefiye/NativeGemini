import QtQuick

Item {
    id: root

    Canvas {
        id: glow
        anchors.horizontalCenter: portrait.horizontalCenter
        anchors.bottom: portrait.bottom
        width: portrait.width * 0.72
        height: portrait.height * 0.56
        property color glowColor: appController.themeBackground

        onGlowColorChanged: requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()

        onPaint: {
            var ctx = getContext("2d")
            var cx = width / 2
            var cy = height / 2
            var radius = Math.min(width, height) / 2
            ctx.clearRect(0, 0, width, height)
            ctx.save()
            ctx.translate(cx, cy)
            ctx.scale(width / height, 1)

            var gradient = ctx.createRadialGradient(0, 0, radius * 0.08, 0, 0, radius)
            gradient.addColorStop(0, Qt.rgba(glowColor.r, glowColor.g, glowColor.b, 0.62))
            gradient.addColorStop(0.52, Qt.rgba(glowColor.r, glowColor.g, glowColor.b, 0.34))
            gradient.addColorStop(1, Qt.rgba(glowColor.r, glowColor.g, glowColor.b, 0))

            ctx.fillStyle = gradient
            ctx.beginPath()
            ctx.arc(0, 0, radius, 0, Math.PI * 2)
            ctx.fill()
            ctx.restore()
        }
    }

    Image {
        id: portrait
        anchors.fill: parent
        source: {
            if (appController.status === "Thinking") return appController.thinkingUrl
            if (appController.status === "Error") return appController.errorUrl
            return appController.currentPortraitUrl
        }
        fillMode: Image.PreserveAspectFit
        smooth: true
    }
}
