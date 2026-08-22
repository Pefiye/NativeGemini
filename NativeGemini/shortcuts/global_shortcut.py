from __future__ import annotations

import asyncio
import logging
import threading
import uuid

from PySide6.QtCore import QObject, Signal, Slot

log = logging.getLogger(__name__)


GLOBAL_SHORTCUTS_XML = """
<node>
  <interface name="org.freedesktop.portal.GlobalShortcuts">
    <method name="CreateSession">
      <arg name="options" type="a{sv}" direction="in"/>
      <arg name="handle" type="o" direction="out"/>
    </method>
    <method name="BindShortcuts">
      <arg name="session_handle" type="o" direction="in"/>
      <arg name="shortcuts" type="a(sa{sv})" direction="in"/>
      <arg name="parent_window" type="s" direction="in"/>
      <arg name="options" type="a{sv}" direction="in"/>
      <arg name="handle" type="o" direction="out"/>
    </method>
    <signal name="Activated">
      <arg name="session_handle" type="o"/>
      <arg name="shortcut_id" type="s"/>
      <arg name="timestamp" type="t"/>
      <arg name="options" type="a{sv}"/>
    </signal>
  </interface>
</node>
"""

REQUEST_XML = """
<node>
  <interface name="org.freedesktop.portal.Request">
    <method name="Close"/>
    <signal name="Response">
      <arg name="response" type="u"/>
      <arg name="results" type="a{sv}"/>
    </signal>
  </interface>
</node>
"""


class GlobalShortcut(QObject):
    activated = Signal()
    statusChanged = Signal(str)

    SERVICE = "org.freedesktop.portal.Desktop"
    PATH = "/org/freedesktop/portal/desktop"
    INTERFACE = "org.freedesktop.portal.GlobalShortcuts"
    SHORTCUT_ID = "toggle-overlay"

    def __init__(self, hotkey: str = "Meta+G", parent: QObject | None = None) -> None:
        super().__init__(parent)
        self.hotkey = hotkey
        self.session_handle = ""
        self._registered = False
        self._thread: threading.Thread | None = None

    def register(self) -> bool:
        if self._thread and self._thread.is_alive():
            return self._registered
        self._thread = threading.Thread(target=self._thread_main, daemon=True)
        self._thread.start()
        return True

    def _thread_main(self) -> None:
        try:
            asyncio.run(self._register_async())
        except Exception as exc:  # pragma: no cover - depends on live portal
            log.exception("Global shortcut registration failed")
            self.statusChanged.emit(f"Global hotkey unavailable: {exc}")

    async def _register_async(self) -> None:
        try:
            from dbus_next import Variant
            from dbus_next.aio import MessageBus
            from dbus_next.introspection import Node
        except Exception as exc:
            self.statusChanged.emit(f"dbus-next unavailable; global hotkey disabled: {exc}")
            return False

        bus = await MessageBus().connect()
        introspection = Node.parse(GLOBAL_SHORTCUTS_XML)
        obj = bus.get_proxy_object(self.SERVICE, self.PATH, introspection)
        iface = obj.get_interface(self.INTERFACE)
        token = uuid.uuid4().hex
        request_handle = await iface.call_create_session(
            {
                "handle_token": Variant("s", uuid.uuid4().hex),
                "session_handle_token": Variant("s", token),
            }
        )
        response, results = await self._wait_for_response(bus, request_handle)
        if response != 0:
            self.statusChanged.emit(f"Shortcut session was not approved by the portal: response {response}")
            return
        session_variant = results.get("session_handle")
        if session_variant is None:
            self.statusChanged.emit("GlobalShortcuts portal did not return a session handle.")
            return
        self.session_handle = str(session_variant.value)

        shortcuts = [
            [
                self.SHORTCUT_ID,
                {
                    "description": Variant("s", "Show or hide NativeGemini"),
                    "preferred_trigger": Variant("s", self.hotkey),
                },
            ]
        ]
        bind_request = await iface.call_bind_shortcuts(
            self.session_handle,
            shortcuts,
            "",
            {"handle_token": Variant("s", uuid.uuid4().hex)},
        )
        bind_response, _bind_results = await self._wait_for_response(bus, bind_request)
        if bind_response != 0:
            self.statusChanged.emit(f"Could not bind {self.hotkey}: portal response {bind_response}")
            return

        iface.on_activated(self._on_activated)
        self._registered = True
        log.debug("Global hotkey registered: %s", self.hotkey)
        await asyncio.Event().wait()

    async def _wait_for_response(self, bus, request_handle: str) -> tuple[int, dict]:
        from dbus_next.introspection import Node

        loop = asyncio.get_running_loop()
        future: asyncio.Future = loop.create_future()
        request_obj = bus.get_proxy_object(self.SERVICE, request_handle, Node.parse(REQUEST_XML))
        request_iface = request_obj.get_interface("org.freedesktop.portal.Request")

        def on_response(response: int, results: dict) -> None:
            if not future.done():
                future.set_result((response, results))

        request_iface.on_response(on_response)
        return await asyncio.wait_for(future, timeout=60)

    @Slot(object, str, int, object)
    def _on_activated(self, session_handle, shortcut_id: str, timestamp: int, options: dict) -> None:
        del timestamp, options
        if str(session_handle) == self.session_handle and shortcut_id == self.SHORTCUT_ID:
            self.activated.emit()

    @property
    def registered(self) -> bool:
        return self._registered
