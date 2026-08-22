from __future__ import annotations

import argparse
import logging
import mimetypes
import os
import sys
import tempfile
import threading
import uuid
from dataclasses import dataclass
from pathlib import Path
from typing import Any
from urllib.parse import unquote, urlparse

from PySide6.QtCore import QObject, Property, QTimer, QUrl, Signal, Slot
from PySide6.QtGui import QAction, QGuiApplication, QIcon
from PySide6.QtQml import QQmlContext
from PySide6.QtWidgets import QApplication, QMenu, QSystemTrayIcon

from NativeGemini.character import Character, CharacterLoadError, load_character, load_first_character
from NativeGemini.config import AppConfig, ConfigStore, SecretStore
from NativeGemini.gemini import GeminiClient, GeminiError, ImageAttachment, TextAttachment
from NativeGemini.overlay import OverlayWindow
from NativeGemini.shortcuts import GlobalShortcut
from NativeGemini.storage.db import Database, title_from_prompt
from NativeGemini.storage.models import Message


logging.basicConfig(level=logging.INFO, format="%(levelname)s %(name)s: %(message)s")
log = logging.getLogger("NativeGemini")
SUPPORTED_IMAGE_MIME_TYPES = {"image/png", "image/jpeg", "image/webp", "image/heic", "image/heif"}
SUPPORTED_TEXT_SUFFIXES = {".txt", ".md", ".markdown"}
MAX_PENDING_ATTACHMENTS = 10
MAX_PENDING_ATTACHMENT_BYTES = 18 * 1024 * 1024
MAX_PENDING_TEXT_BYTES = 512 * 1024
LONG_PASTE_ATTACHMENT_CHARS = 1800


def as_url(path: Path | None) -> str:
    return path.resolve().as_uri() if path else ""


def path_from_url(value: object) -> Path:
    text = value.toString() if isinstance(value, QUrl) else str(value)
    if text.startswith("file://"):
        return Path(unquote(urlparse(text).path))
    return Path(text)


@dataclass(frozen=True)
class PendingAttachment:
    id: str
    path: Path
    mime_type: str
    kind: str
    temporary: bool = False
    pasted: bool = False

    @property
    def name(self) -> str:
        return "Pasted text" if self.pasted else self.path.name

    @property
    def size(self) -> int:
        try:
            return self.path.stat().st_size
        except OSError:
            return 0

    @property
    def extension(self) -> str:
        if self.pasted:
            return "TXT"
        suffix = self.path.suffix.removeprefix(".")
        return (suffix or self.kind).upper()[:8]


class Controller(QObject):
    messagesChanged = Signal()
    conversationsChanged = Signal()
    conversationSearchChanged = Signal()
    currentConversationChanged = Signal()
    characterChanged = Signal()
    statusChanged = Signal()
    modelsChanged = Signal()
    selectedModelChanged = Signal()
    groundingModeChanged = Signal()
    activityModeChanged = Signal()
    pendingImagesChanged = Signal()
    overlayVisibleChanged = Signal()
    apiKeyStateChanged = Signal()
    tavilyApiKeyStateChanged = Signal()
    usageSummaryChanged = Signal()
    activityModeRequested = Signal(str)
    geminiFinished = Signal(object, str)
    modelsLoaded = Signal(list, str)
    titleGenerated = Signal(int, str, str)

    def __init__(self, project_root: Path) -> None:
        super().__init__()
        self.project_root = project_root
        self.config_store = ConfigStore()
        self.config: AppConfig = self.config_store.load()
        self.secrets = SecretStore()
        self.db = Database()
        self._status = "Ready"
        self._overlay_visible = False
        self._messages: list[Message] = []
        self._conversation_id = 0
        self._conversation_search = ""
        self._activity_mode = ""
        self._animated_message_id = 0
        self._pending_attachments: list[PendingAttachment] = []
        self._models: list[str] = []
        self._character: Character | None = None
        self._current_portrait_path: Path | None = None
        self._pending_title_requests: dict[int, tuple[str, str]] = {}
        self.geminiFinished.connect(self._on_gemini_finished)
        self.modelsLoaded.connect(self._on_models_loaded)
        self.titleGenerated.connect(self._on_title_generated)
        self.activityModeRequested.connect(self.set_activity_mode)
        self._load_initial_character()
        self._load_initial_conversation()

    def _load_initial_character(self) -> None:
        candidates = []
        if self.config.active_character_folder:
            candidates.append(Path(self.config.active_character_folder))
        candidates.append(self.project_root / "Character")
        for candidate in candidates:
            try:
                if candidate.is_dir() and (candidate / "emotions").exists():
                    self._character = load_character(candidate)
                else:
                    self._character = load_first_character(candidate)
                if self._character:
                    self.config.active_character_folder = str(self._character.folder)
                    self.config_store.save(self.config)
                    self._current_portrait_path = self._character.portrait_for("neutral")
                    self.characterChanged.emit()
                    return
            except CharacterLoadError as exc:
                self._status = str(exc)
        self._status = "No valid character folder selected."

    def _load_initial_conversation(self) -> None:
        conversations = self.db.list_conversations()
        if conversations:
            self._conversation_id = conversations[0].id
            self._messages = self.db.list_messages(self._conversation_id)

    @Property(bool, notify=overlayVisibleChanged)
    def overlayVisible(self) -> bool:
        return self._overlay_visible

    @overlayVisible.setter
    def overlayVisible(self, value: bool) -> None:
        if self._overlay_visible != value:
            self._overlay_visible = value
            self.overlayVisibleChanged.emit()

    @Property(str, notify=statusChanged)
    def status(self) -> str:
        return self._status

    def set_status(self, status: str) -> None:
        self._status = status
        self.statusChanged.emit()

    @Property(bool, notify=apiKeyStateChanged)
    def apiKeySaved(self) -> bool:
        return self.config.api_key_saved

    def _set_api_key_saved(self, saved: bool) -> None:
        if self.config.api_key_saved != saved:
            self.config.api_key_saved = saved
            self.config_store.save(self.config)
            self.apiKeyStateChanged.emit()

    @Property(bool, notify=tavilyApiKeyStateChanged)
    def tavilyApiKeySaved(self) -> bool:
        return self.config.tavily_api_key_saved

    def _set_tavily_api_key_saved(self, saved: bool) -> None:
        if self.config.tavily_api_key_saved != saved:
            self.config.tavily_api_key_saved = saved
            self.config_store.save(self.config)
            self.tavilyApiKeyStateChanged.emit()

    @Property("QVariantList", notify=messagesChanged)
    def messages(self) -> list[dict[str, Any]]:
        last_user_id = 0
        for item in reversed(self._messages):
            if item.role == "user":
                last_user_id = item.id
                break
        return [
            {
                "id": item.id,
                "role": item.role,
                "content": item.content,
                "emotion": item.emotion or "",
                "canEdit": item.id == last_user_id,
                "animate": item.id == self._animated_message_id,
            }
            for item in self._messages
        ]

    @Property("QVariantList", notify=conversationsChanged)
    def conversations(self) -> list[dict[str, Any]]:
        return [
            {"id": item.id, "title": item.title, "created_at": item.created_at}
            for item in self.db.search_conversations(self._conversation_search)
        ]

    @Property(str, notify=conversationSearchChanged)
    def conversationSearch(self) -> str:
        return self._conversation_search

    @Property(int, notify=currentConversationChanged)
    def currentConversationId(self) -> int:
        return self._conversation_id

    @Property(str, notify=characterChanged)
    def characterName(self) -> str:
        return self._character.name if self._character else "No Character"

    @Property(str, notify=characterChanged)
    def characterIconUrl(self) -> str:
        return as_url(self._character.icon_path if self._character else None)

    @Property(str, notify=characterChanged)
    def portraitUrl(self) -> str:
        return as_url(self._character.portrait_for("neutral") if self._character else None)

    @Property(str, notify=characterChanged)
    def currentPortraitUrl(self) -> str:
        return as_url(self._current_portrait_path)

    @Property(str, notify=characterChanged)
    def thinkingUrl(self) -> str:
        return as_url(self._character.thinking_path if self._character else None)

    @Property(str, notify=characterChanged)
    def errorUrl(self) -> str:
        if not self._character:
            return ""
        return as_url(self._character.error_path or self._character.portrait_for("neutral"))

    @Property("QStringList", notify=characterChanged)
    def emotions(self) -> list[str]:
        return self._character.emotion_names if self._character else []

    @Property(str, notify=characterChanged)
    def themeBackground(self) -> str:
        return self._character.background if self._character else "#A1FF9E"

    @Property(str, notify=characterChanged)
    def themeBorder(self) -> str:
        return self._character.border if self._character else "#FF8B43"

    @Property(str, constant=True)
    def homeUrl(self) -> str:
        return Path.home().resolve().as_uri()

    @Property("QStringList", notify=modelsChanged)
    def models(self) -> list[str]:
        return self._models

    @Property(str, notify=selectedModelChanged)
    def selectedModel(self) -> str:
        return self.config.selected_model

    @Property(str, notify=groundingModeChanged)
    def groundingMode(self) -> str:
        return self.config.grounding_mode if self.config.grounding_mode in {"auto", "always", "off"} else "auto"

    @Property(str, notify=activityModeChanged)
    def activityMode(self) -> str:
        return self._activity_mode

    @Property("QVariantList", notify=pendingImagesChanged)
    def pendingImages(self) -> list[dict[str, Any]]:
        return [
            {
                "id": item.id,
                "name": item.name,
                "url": as_url(item.path) if item.kind == "image" else "",
                "size": item.size,
                "kind": item.kind,
                "extension": item.extension,
            }
            for item in self._pending_attachments
        ]

    @Property("QVariantMap", notify=usageSummaryChanged)
    def usageSummary(self) -> dict[str, int]:
        return self.db.usage_summary()

    def set_activity_mode(self, mode: str) -> None:
        normalized = mode if mode in {"typing", "searching"} else ""
        if self._activity_mode != normalized:
            self._activity_mode = normalized
            self.activityModeChanged.emit()

    @Slot()
    def toggleOverlay(self) -> None:
        self.overlayVisible = not self.overlayVisible

    @Slot()
    def hideOverlay(self) -> None:
        self.overlayVisible = False

    @Slot(str)
    def saveApiKey(self, api_key: str) -> None:
        ok, message = self.secrets.set_api_key(api_key)
        self.set_status(message)
        if ok:
            self._set_api_key_saved(True)
            self.refreshModels()

    @Slot(str)
    def saveTavilyApiKey(self, api_key: str) -> None:
        ok, message = self.secrets.set_tavily_api_key(api_key)
        self.set_status(f"Tavily {message[0].lower()}{message[1:]}" if message else "")
        if ok:
            self._set_tavily_api_key_saved(True)

    @Slot(str)
    def loadCharacterFolder(self, folder_url: str) -> None:
        raw = folder_url
        if raw.startswith("file://"):
            raw = unquote(urlparse(raw).path)
        try:
            self._character = load_character(raw)
        except CharacterLoadError as exc:
            self.set_status(str(exc))
            return
        self.config.active_character_folder = str(self._character.folder)
        self.config_store.save(self.config)
        self._current_portrait_path = self._character.portrait_for("neutral")
        self.characterChanged.emit()
        self.set_status(f"Loaded character: {self._character.name}")

    @Slot(str)
    def setSelectedModel(self, model: str) -> None:
        if model and model != self.config.selected_model:
            self.config.selected_model = model
            self.config_store.save(self.config)
            self.selectedModelChanged.emit()

    @Slot(str)
    def setGroundingMode(self, mode: str) -> None:
        normalized = mode if mode in {"auto", "always", "off"} else "auto"
        if normalized != self.groundingMode:
            self.config.grounding_mode = normalized
            self.config_store.save(self.config)
            self.groundingModeChanged.emit()

    @Slot()
    def refreshModels(self) -> None:
        api_key = self.secrets.get_api_key()
        if not api_key:
            self._set_api_key_saved(False)
            detail = self.secrets.last_error or "Save a Gemini API key to load models."
            self.set_status(detail)
            return
        self._set_api_key_saved(True)

        def worker() -> None:
            try:
                client = GeminiClient(api_key, self.config.selected_model or "models/gemini-2.5-flash")
                models = client.list_models()
                error = ""
            except Exception as exc:
                models = []
                error = str(exc)
            self.modelsLoaded.emit(models, error)

        threading.Thread(target=worker, daemon=True).start()

    @Slot(list, str)
    def _on_models_loaded(self, models: list[str], error: str) -> None:
        if error:
            self.set_status(error)
            return
        self._models = models
        if models and (not self.config.selected_model or self.config.selected_model not in models):
            self.config.selected_model = models[0]
            self.config_store.save(self.config)
            self.selectedModelChanged.emit()
        self.modelsChanged.emit()
        self.set_status(f"Loaded {len(models)} Gemini models.")

    @Slot(int)
    def selectConversation(self, conversation_id: int) -> None:
        if self._conversation_id == conversation_id:
            return
        self.set_activity_mode("")
        self._animated_message_id = 0
        self._conversation_id = conversation_id
        self._messages = self.db.list_messages(conversation_id)
        self.currentConversationChanged.emit()
        self.messagesChanged.emit()

    @Slot(int, str)
    def renameConversation(self, conversation_id: int, title: str) -> None:
        self.db.rename_conversation(conversation_id, title)
        self.conversationsChanged.emit()

    @Slot(str)
    def setConversationSearch(self, query: str) -> None:
        if self._conversation_search == query:
            return
        self._conversation_search = query
        self.conversationSearchChanged.emit()
        self.conversationsChanged.emit()

    @Slot()
    def startNewChat(self) -> None:
        changed_search = self._conversation_search != ""
        self._conversation_search = ""
        self.set_activity_mode("")
        self._conversation_id = 0
        self._messages = []
        self._animated_message_id = 0
        self._set_portrait("neutral")
        if changed_search:
            self.conversationSearchChanged.emit()
            self.conversationsChanged.emit()
        self.currentConversationChanged.emit()
        self.messagesChanged.emit()

    @Slot(int)
    def deleteConversation(self, conversation_id: int) -> None:
        self._pending_title_requests.pop(conversation_id, None)
        self.db.delete_conversation(conversation_id)
        if self._conversation_id == conversation_id:
            self._conversation_id = 0
            self._messages = []
            self._animated_message_id = 0
            conversations = self.db.search_conversations(self._conversation_search)
            if conversations:
                self._conversation_id = conversations[0].id
                self._messages = self.db.list_messages(self._conversation_id)
            self.currentConversationChanged.emit()
            self.messagesChanged.emit()
        self.conversationsChanged.emit()

    def _cleanup_pending_attachment(self, attachment: PendingAttachment) -> None:
        if attachment.temporary:
            try:
                attachment.path.unlink(missing_ok=True)
            except OSError:
                pass

    def _clear_pending_images(self, emit: bool = True) -> None:
        for attachment in self._pending_attachments:
            self._cleanup_pending_attachment(attachment)
        self._pending_attachments = []
        if emit:
            self.pendingImagesChanged.emit()

    @staticmethod
    def _attachment_mime_type(path: Path) -> str:
        mime_type = mimetypes.guess_type(path.name)[0] or ""
        if mime_type == "image/jpg":
            return "image/jpeg"
        if path.suffix.lower() in {".md", ".markdown"}:
            return "text/markdown"
        if path.suffix.lower() == ".txt":
            return "text/plain"
        return mime_type

    @staticmethod
    def _read_text_attachment(path: Path) -> str:
        return path.read_text(encoding="utf-8-sig", errors="replace")

    def _add_pending_attachment_path(self, path: Path, temporary: bool = False, pasted: bool = False) -> bool:
        if len(self._pending_attachments) >= MAX_PENDING_ATTACHMENTS:
            self.set_status(f"Maximum {MAX_PENDING_ATTACHMENTS} attachments per prompt.")
            if temporary:
                try:
                    path.unlink(missing_ok=True)
                except OSError:
                    pass
            return False
        try:
            path = path.resolve()
        except OSError:
            pass
        if not path.exists() or not path.is_file():
            self.set_status("Attachment file was not found.")
            if temporary:
                try:
                    path.unlink(missing_ok=True)
                except OSError:
                    pass
            return False
        mime_type = self._attachment_mime_type(path)
        suffix = path.suffix.lower()
        if mime_type in SUPPORTED_IMAGE_MIME_TYPES:
            kind = "image"
        elif suffix in SUPPORTED_TEXT_SUFFIXES:
            kind = "text"
        else:
            self.set_status("Unsupported attachment type. Use images, TXT, or Markdown.")
            if temporary:
                try:
                    path.unlink(missing_ok=True)
                except OSError:
                    pass
            return False
        attachment_size = path.stat().st_size
        if kind == "text" and attachment_size > MAX_PENDING_TEXT_BYTES:
            self.set_status("Text attachment is too large for one prompt.")
            if temporary:
                try:
                    path.unlink(missing_ok=True)
                except OSError:
                    pass
            return False
        total_size = sum(item.size for item in self._pending_attachments) + attachment_size
        if total_size > MAX_PENDING_ATTACHMENT_BYTES:
            self.set_status("Attachments are too large for one prompt.")
            if temporary:
                try:
                    path.unlink(missing_ok=True)
                except OSError:
                    pass
            return False
        existing_paths = {item.path.resolve() for item in self._pending_attachments if item.path.exists()}
        if not temporary and path.resolve() in existing_paths:
            return False
        self._pending_attachments.append(PendingAttachment(str(uuid.uuid4()), path, mime_type, kind, temporary, pasted))
        return True

    def _add_pending_text_content(self, text: str, name: str = "pasted-text.md") -> bool:
        temp_dir = Path(tempfile.gettempdir()) / "NativeGemini"
        temp_dir.mkdir(parents=True, exist_ok=True)
        path = temp_dir / f"{Path(name).stem}-{uuid.uuid4().hex}{Path(name).suffix or '.txt'}"
        path.write_text(text, encoding="utf-8")
        return self._add_pending_attachment_path(path, True, True)

    @Slot("QVariantList", result=bool)
    def addFileAttachments(self, urls: list[object]) -> bool:
        changed = False
        for item in urls:
            try:
                changed = self._add_pending_attachment_path(path_from_url(item)) or changed
            except OSError as exc:
                self.set_status(f"Could not attach file: {exc}")
        if changed:
            self.pendingImagesChanged.emit()
        return changed

    @Slot("QVariantList", result=bool)
    def addImageAttachments(self, urls: list[object]) -> bool:
        return self.addFileAttachments(urls)

    @Slot(result=bool)
    def addClipboardAttachment(self) -> bool:
        clipboard = QGuiApplication.clipboard()
        mime_data = clipboard.mimeData()
        if mime_data.hasUrls():
            return self.addFileAttachments(list(mime_data.urls()))
        image = clipboard.image()
        if not image.isNull():
            temp_dir = Path(tempfile.gettempdir()) / "NativeGemini"
            temp_dir.mkdir(parents=True, exist_ok=True)
            path = temp_dir / f"clipboard-{uuid.uuid4().hex}.png"
            if not image.save(str(path), "PNG"):
                self.set_status("Could not attach clipboard image.")
                return False
            if self._add_pending_attachment_path(path, True):
                self.pendingImagesChanged.emit()
                return True
            return False
        clipboard_text = clipboard.text()
        if len(clipboard_text.strip()) >= LONG_PASTE_ATTACHMENT_CHARS:
            if self._add_pending_text_content(clipboard_text, "pasted-text.md"):
                self.pendingImagesChanged.emit()
                return True
        return False

    @Slot(result=bool)
    def addClipboardImage(self) -> bool:
        return self.addClipboardAttachment()

    @Slot(str)
    def removePendingImage(self, image_id: str) -> None:
        kept = []
        removed = False
        for attachment in self._pending_attachments:
            if attachment.id == image_id:
                self._cleanup_pending_attachment(attachment)
                removed = True
            else:
                kept.append(attachment)
        if removed:
            self._pending_attachments = kept
            self.pendingImagesChanged.emit()

    @Slot()
    def clearPendingImages(self) -> None:
        self._clear_pending_images()

    @Slot(str)
    def sendPrompt(self, prompt: str) -> None:
        text = prompt.strip()
        image_attachments = [
            ImageAttachment(item.path.read_bytes(), item.mime_type)
            for item in self._pending_attachments
            if item.kind == "image"
        ]
        text_attachments = [
            TextAttachment(item.name, self._read_text_attachment(item.path), item.mime_type)
            for item in self._pending_attachments
            if item.kind == "text"
        ]
        if not text and not image_attachments and not text_attachments:
            return
        if not text:
            text = "Please analyze the attached file(s)."
        stored_text = text
        attachment_count = len(image_attachments) + len(text_attachments)
        if attachment_count:
            stored_text += f"\n\n[Attached {attachment_count} file{'s' if attachment_count != 1 else ''} for this request.]"
        if self._conversation_id == 0:
            fallback_title = title_from_prompt(text)
            conversation = self.db.create_conversation(fallback_title)
            self._conversation_id = conversation.id
            self._pending_title_requests[conversation.id] = (text, fallback_title)
            self.currentConversationChanged.emit()
            self.conversationsChanged.emit()
        self.db.add_message(self._conversation_id, "user", stored_text)
        self._clear_pending_images()
        self._messages = self.db.list_messages(self._conversation_id)
        self.messagesChanged.emit()
        self.set_status("Thinking")
        self._set_portrait("thinking")
        self._call_gemini(image_attachments, text_attachments)

    @Slot(str)
    def editLastPrompt(self, prompt: str) -> None:
        if not prompt.strip() or self._conversation_id == 0:
            return
        self.db.replace_last_prompt(self._conversation_id, prompt.strip())
        self._messages = self.db.list_messages(self._conversation_id)
        self.messagesChanged.emit()
        self.set_status("Thinking")
        self._set_portrait("thinking")
        self._call_gemini()

    @Slot(str)
    def copyMessageText(self, text: str) -> None:
        QGuiApplication.clipboard().setText(text)

    @Slot(int)
    def markMessageAnimationDone(self, message_id: int) -> None:
        if self._animated_message_id == message_id:
            self._animated_message_id = 0

    def _call_gemini(
        self,
        image_attachments: list[ImageAttachment] | None = None,
        text_attachments: list[TextAttachment] | None = None,
    ) -> None:
        api_key = self.secrets.get_api_key()
        if not api_key:
            self._set_api_key_saved(False)
            self._append_error(self.secrets.last_error or "Gemini API key is not configured.")
            return
        self._set_api_key_saved(True)
        if not self.config.selected_model:
            self._append_error("No Gemini model selected. Open Settings and refresh models.")
            return
        history = list(self._messages)
        emotions = self.emotions
        is_grounding = GeminiClient.grounding_enabled(self.config.grounding_mode, history)
        may_ground = self.config.grounding_mode != "off"
        tavily_api_key = self.secrets.get_tavily_api_key() if may_ground else ""
        if may_ground and tavily_api_key:
            self._set_tavily_api_key_saved(True)
        self.set_activity_mode("searching" if is_grounding else "typing")

        def worker() -> None:
            try:
                client = GeminiClient(api_key, self.config.selected_model, tavily_api_key)
                result = client.generate(
                    history,
                    emotions,
                    self.config.grounding_mode,
                    image_attachments,
                    text_attachments,
                    self.activityModeRequested.emit,
                )
                self.geminiFinished.emit(result, "")
            except Exception as exc:
                self.geminiFinished.emit(None, str(exc))

        threading.Thread(target=worker, daemon=True).start()

    def _generate_conversation_title(self, conversation_id: int, prompt: str, fallback_title: str) -> None:
        api_key = self.secrets.get_api_key()
        if not api_key or not self.config.selected_model:
            return

        def worker() -> None:
            title = ""
            try:
                client = GeminiClient(api_key, self.config.selected_model)
                title = client.generate_title(prompt)
            except Exception as exc:
                log.debug("Could not generate conversation title: %s", exc)
            self.titleGenerated.emit(conversation_id, title, fallback_title)

        threading.Thread(target=worker, daemon=True).start()

    @Slot(int, str, str)
    def _on_title_generated(self, conversation_id: int, title: str, fallback_title: str) -> None:
        if not title.strip():
            return
        try:
            conversation = self.db.get_conversation(conversation_id)
        except KeyError:
            return
        if conversation.title != fallback_title:
            return
        self.db.rename_conversation(conversation_id, title)
        self.conversationsChanged.emit()

    @Slot(object, str)
    def _on_gemini_finished(self, result: object, error: str) -> None:
        if error:
            self._append_error(error)
            return
        assert result is not None
        self.set_activity_mode("")
        emotion = getattr(result, "emotion", "neutral")
        answer = getattr(result, "answer", "")
        conversation_id = self._conversation_id
        message = self.db.add_message(conversation_id, "assistant", answer, emotion)
        self.db.add_usage_event(
            self.config.selected_model,
            conversation_id,
            getattr(result, "input_tokens_estimate", 0),
            getattr(result, "output_tokens_estimate", 0),
            bool(getattr(result, "grounding_attempted", getattr(result, "grounded", False))),
            getattr(result, "tavily_searches", 0),
        )
        self.usageSummaryChanged.emit()
        self._animated_message_id = message.id
        self._set_portrait(emotion)
        self._messages = self.db.list_messages(conversation_id)
        self.messagesChanged.emit()
        self.set_status("Ready")
        pending_title = self._pending_title_requests.pop(conversation_id, None)
        if pending_title:
            prompt, fallback_title = pending_title
            self._generate_conversation_title(conversation_id, prompt, fallback_title)

    def _append_error(self, reason: str) -> None:
        self.set_activity_mode("")
        if self._conversation_id == 0:
            conversation = self.db.create_conversation("Error")
            self._conversation_id = conversation.id
            self.currentConversationChanged.emit()
            self.conversationsChanged.emit()
        self._pending_title_requests.pop(self._conversation_id, None)
        self.db.add_message(self._conversation_id, "assistant", f"Something went wrong: {reason}. Try again?", "error")
        self._set_portrait("error")
        self._messages = self.db.list_messages(self._conversation_id)
        self.messagesChanged.emit()
        self.set_status("Error")

    def _set_portrait(self, emotion: str) -> None:
        if self._character is None:
            return
        self._current_portrait_path = self._character.portrait_for(emotion)
        self.characterChanged.emit()


def create_tray(app: QApplication, controller: Controller, window: OverlayWindow) -> QSystemTrayIcon:
    tray = QSystemTrayIcon()
    icon = QIcon.fromTheme("assistant")
    if icon.isNull():
        icon = app.style().standardIcon(app.style().StandardPixmap.SP_ComputerIcon)
    tray.setIcon(icon)
    menu = QMenu()
    show_action = QAction("Show / Hide", tray)
    show_action.triggered.connect(controller.toggleOverlay)
    quit_action = QAction("Quit", tray)
    quit_action.triggered.connect(app.quit)
    menu.addAction(show_action)
    menu.addAction(quit_action)
    tray.setContextMenu(menu)
    tray.activated.connect(lambda reason: controller.toggleOverlay() if reason == QSystemTrayIcon.ActivationReason.Trigger else None)
    tray.show()
    return tray


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--hidden", action="store_true", help="Start with the overlay hidden.")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv or sys.argv[1:])
    os.environ.setdefault("QT_QUICK_CONTROLS_STYLE", "Basic")
    app = QApplication(sys.argv)
    app.setApplicationName("NativeGemini")
    app.setQuitOnLastWindowClosed(False)

    project_root = Path(__file__).resolve().parents[1]
    controller = Controller(project_root)
    qml_path = project_root / "NativeGemini" / "qml" / "Main.qml"
    window = OverlayWindow()
    context: QQmlContext = window.rootContext()
    context.setContextProperty("appController", controller)
    window.load(qml_path)

    shortcut = GlobalShortcut(controller.config.hotkey)
    shortcut.activated.connect(controller.toggleOverlay)
    shortcut.statusChanged.connect(controller.set_status)
    QTimer.singleShot(250, shortcut.register)

    controller.overlayVisibleChanged.connect(lambda: window.set_overlay_visible(controller.overlayVisible))
    window.dismissRequested.connect(controller.hideOverlay)
    tray = create_tray(app, controller, window)
    app.aboutToQuit.connect(tray.hide)

    if not args.hidden:
        controller.overlayVisible = True
    else:
        window.hide()

    return app.exec()


if __name__ == "__main__":
    raise SystemExit(main())
