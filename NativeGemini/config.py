from __future__ import annotations

import json
import os
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any


APP_NAME = "NativeGemini"


def config_dir() -> Path:
    root = os.environ.get("XDG_CONFIG_HOME")
    base = Path(root) if root else Path.home() / ".config"
    path = base / APP_NAME
    path.mkdir(parents=True, exist_ok=True)
    return path


@dataclass
class AppConfig:
    hotkey: str = "Meta+G"
    active_character_folder: str = ""
    selected_model: str = ""
    grounding_mode: str = "auto"
    launch_hidden: bool = False
    api_key_saved: bool = False
    tavily_api_key_saved: bool = False


class ConfigStore:
    def __init__(self, path: Path | None = None) -> None:
        self.path = path or config_dir() / "config.json"

    def load(self) -> AppConfig:
        if not self.path.exists():
            return AppConfig()
        try:
            data = json.loads(self.path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            return AppConfig()
        allowed = {field.name for field in AppConfig.__dataclass_fields__.values()}
        return AppConfig(**{key: value for key, value in data.items() if key in allowed})

    def save(self, config: AppConfig) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        payload = json.dumps(asdict(config), indent=2, sort_keys=True)
        self.path.write_text(payload + "\n", encoding="utf-8")
        os.chmod(self.path, 0o600)


class SecretStore:
    """API-key storage backed by the desktop Secret Service.

    The app intentionally does not fall back to plaintext API-key storage.
    """

    SERVICE = "NativeGemini"
    USERNAME = "gemini-api-key"
    LABEL = "NativeGemini Gemini API key"
    TAVILY_USERNAME = "tavily-api-key"
    TAVILY_LABEL = "NativeGemini Tavily API key"

    def __init__(self) -> None:
        self._error = ""

    @property
    def last_error(self) -> str:
        return self._error

    def available(self) -> bool:
        try:
            import secretstorage  # noqa: F401
        except Exception as exc:  # pragma: no cover - depends on host packages
            self._error = f"Secret Service support is unavailable: {exc}"
            return False
        return True

    @property
    def attributes(self) -> dict[str, str]:
        return {"application": self.SERVICE, "kind": self.USERNAME}

    def _attributes(self, kind: str) -> dict[str, str]:
        return {"application": self.SERVICE, "kind": kind}

    def _unlock_collection(self, collection) -> None:
        if collection.is_locked():
            collection.unlock()

    def _unlock_item(self, item) -> None:
        if item.is_locked():
            item.unlock()

    def _find_items(self, collection, attributes: dict[str, str] | None = None, label: str | None = None) -> list:
        attrs = attributes or self.attributes
        item_label = label or self.LABEL
        items = list(collection.search_items(attrs))
        if items:
            return items
        # KWallet/Secret Service implementations can vary in how searchable
        # attributes behave after migration or relaunch. Match by label too,
        # but never inspect or log the stored secret while doing so.
        matches = []
        for item in collection.get_all_items():
            try:
                attrs = item.get_attributes()
                has_attributes = all(attrs.get(key) == value for key, value in (attributes or self.attributes).items())
                if has_attributes or item.get_label() == item_label:
                    matches.append(item)
            except Exception:
                continue
        return matches

    def get_secret(self, kind: str, label: str) -> str:
        try:
            import secretstorage

            bus = secretstorage.dbus_init()
            collection = secretstorage.get_default_collection(bus)
            self._unlock_collection(collection)
            for item in self._find_items(collection, self._attributes(kind), label):
                self._unlock_item(item)
                secret = item.get_secret().decode("utf-8").strip()
                if secret:
                    return secret
        except Exception as exc:  # pragma: no cover - host integration
            self._error = f"Could not read {label} from Secret Service: {exc}"
        return ""

    def set_secret(self, kind: str, label: str, api_key: str) -> tuple[bool, str]:
        if not api_key.strip():
            return False, "API key is empty."
        try:
            import secretstorage

            bus = secretstorage.dbus_init()
            collection = secretstorage.get_default_collection(bus)
            self._unlock_collection(collection)
            attributes = self._attributes(kind)
            for item in self._find_items(collection, attributes, label):
                item.delete()
            collection.create_item(
                label,
                attributes,
                api_key.strip().encode("utf-8"),
                replace=True,
            )
            return True, "API key saved to Secret Service."
        except Exception as exc:  # pragma: no cover - host integration
            self._error = str(exc)
            return False, f"Could not save API key securely: {exc}"

    def get_api_key(self) -> str:
        return self.get_secret(self.USERNAME, self.LABEL)

    def set_api_key(self, api_key: str) -> tuple[bool, str]:
        return self.set_secret(self.USERNAME, self.LABEL, api_key)

    def get_tavily_api_key(self) -> str:
        return self.get_secret(self.TAVILY_USERNAME, self.TAVILY_LABEL)

    def set_tavily_api_key(self, api_key: str) -> tuple[bool, str]:
        return self.set_secret(self.TAVILY_USERNAME, self.TAVILY_LABEL, api_key)


def merge_config(config: AppConfig, changes: dict[str, Any]) -> AppConfig:
    data = asdict(config)
    data.update(changes)
    return AppConfig(**data)
