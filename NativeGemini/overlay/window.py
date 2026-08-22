from __future__ import annotations

from pathlib import Path

from PySide6.QtCore import QObject, QTimer, QUrl, Qt, Signal
from PySide6.QtGui import QColor, QKeyEvent, QWheelEvent
from PySide6.QtQuick import QQuickView


class OverlayWindow(QQuickView):
    dismissRequested = Signal()

    _WHEEL_STEP_MINIMUM = 150.0
    _WHEEL_VIEWPORT_RATIO = 0.20
    _PIXEL_WHEEL_MULTIPLIER = 2.0

    def __init__(self) -> None:
        super().__init__()
        self._message_viewport: QObject | None = None
        self._message_list: QObject | None = None
        self._hide_timer = QTimer(self)
        self._hide_timer.setSingleShot(True)
        self._hide_timer.timeout.connect(self.hide)
        self.activeChanged.connect(self._on_active_changed)
        self.setColor(QColor(0, 0, 0, 0))
        self.setResizeMode(QQuickView.SizeRootObjectToView)
        self.setFlags(
            Qt.WindowType.Tool
            | Qt.WindowType.FramelessWindowHint
            | Qt.WindowType.WindowStaysOnTopHint
        )
        self.position_fullscreen()

    def load(self, qml_path: Path) -> None:
        self.setSource(QUrl.fromLocalFile(str(qml_path)))
        root = self.rootObject()
        if root is not None:
            self._message_viewport = root.findChild(QObject, "messageViewport")
            self._message_list = root.findChild(QObject, "messageList")

    def position_fullscreen(self) -> None:
        screen = self.screen()
        if screen is None:
            return
        geometry = screen.geometry()
        self.setGeometry(geometry)

    def set_overlay_visible(self, visible: bool) -> None:
        root = self.rootObject()
        if visible:
            if self._hide_timer.isActive():
                self._hide_timer.stop()
            self.position_fullscreen()
            self.show()
            self.raise_()
            self.requestActivate()
            if root is not None:
                root.setProperty("overlayVisible", False)
                QTimer.singleShot(0, lambda: root.setProperty("overlayVisible", True))
        else:
            if root is not None:
                root.setProperty("overlayVisible", False)
                self._hide_timer.start(260)
            else:
                self.hide()

    def keyPressEvent(self, event: QKeyEvent) -> None:
        if event.key() == Qt.Key.Key_Escape:
            self.dismissRequested.emit()
            event.accept()
            return
        super().keyPressEvent(event)

    def wheelEvent(self, event: QWheelEvent) -> None:
        if self._scroll_conversation(event):
            event.accept()
            return
        super().wheelEvent(event)

    def _scroll_conversation(self, event: QWheelEvent) -> bool:
        root = self.rootObject()
        viewport = self._message_viewport
        message_list = self._message_list
        if root is None or viewport is None or message_list is None:
            return False
        if not bool(root.property("overlayVisible")) or bool(root.property("settingsOpen")):
            return False

        local_position = viewport.mapFromScene(event.position())
        if not viewport.contains(local_position):
            return False

        angle_delta = event.angleDelta().y()
        pixel_delta = event.pixelDelta().y()
        if angle_delta:
            scroll_direction = 1.0 if angle_delta > 0 else -1.0
            distance_per_step = max(
                self._WHEEL_STEP_MINIMUM,
                float(viewport.property("height")) * self._WHEEL_VIEWPORT_RATIO,
            )
            scroll_delta = scroll_direction * distance_per_step
        elif pixel_delta:
            scroll_delta = pixel_delta * self._PIXEL_WHEEL_MULTIPLIER
        else:
            return False

        viewport_height = float(message_list.property("height"))
        content_height = float(message_list.property("contentHeight"))
        maximum_y = max(0.0, content_height - viewport_height)
        current_y = float(message_list.property("contentY"))
        message_list.setProperty("contentY", max(0.0, min(maximum_y, current_y - scroll_delta)))
        return True

    def _on_active_changed(self) -> None:
        if self.isActive():
            return
        QTimer.singleShot(80, self._dismiss_if_still_inactive)

    def _dismiss_if_still_inactive(self) -> None:
        root = self.rootObject()
        overlay_visible = bool(root.property("overlayVisible")) if root is not None else self.isVisible()
        if self.isVisible() and overlay_visible and not self.isActive():
            self.dismissRequested.emit()
