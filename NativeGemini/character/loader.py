from __future__ import annotations

import configparser
from dataclasses import dataclass
from pathlib import Path


DEFAULT_BACKGROUND = "#A1FF9E"
DEFAULT_BORDER = "#FF8B43"


class CharacterLoadError(ValueError):
    pass


@dataclass(frozen=True)
class Character:
    folder: Path
    name: str
    icon_path: Path
    thinking_path: Path
    error_path: Path | None
    emotions: dict[str, Path]
    background: str
    border: str

    @property
    def emotion_names(self) -> list[str]:
        return sorted(self.emotions)

    def portrait_for(self, emotion: str) -> Path:
        key = emotion.strip().lower()
        if key == "thinking":
            return self.thinking_path
        if key in self.emotions:
            return self.emotions[key]
        if self.error_path and key in {"error", "confused"}:
            return self.error_path
        if "neutral" in self.emotions:
            return self.emotions["neutral"]
        return next(iter(self.emotions.values()), self.thinking_path)


def _normalize_hex(value: str, fallback: str) -> str:
    raw = value.strip().lstrip("#")
    if len(raw) == 6 and all(char in "0123456789abcdefABCDEF" for char in raw):
        return f"#{raw.upper()}"
    return fallback


def load_character(folder: str | Path) -> Character:
    root = Path(folder).expanduser().resolve()
    if not root.exists() or not root.is_dir():
        raise CharacterLoadError(f"Character folder does not exist: {root}")

    icon = root / "icon.png"
    thinking = root / "thinking.png"
    emotions_dir = root / "emotions"
    missing = [str(path.name) for path in (icon, thinking, emotions_dir) if not path.exists()]
    if missing:
        raise CharacterLoadError(f"Character folder is missing: {', '.join(missing)}")
    if not emotions_dir.is_dir():
        raise CharacterLoadError("emotions must be a folder")

    emotions = {
        path.stem.lower(): path.resolve()
        for path in sorted(emotions_dir.glob("*.png"))
        if path.is_file()
    }
    if not emotions:
        raise CharacterLoadError("emotions folder must contain at least one .png")

    parser = configparser.ConfigParser()
    parser.read(root / "char.ini", encoding="utf-8")
    section = parser["Character"] if parser.has_section("Character") else {}
    name = section.get("Name", root.name) if hasattr(section, "get") else root.name
    background = _normalize_hex(section.get("background", ""), DEFAULT_BACKGROUND) if hasattr(section, "get") else DEFAULT_BACKGROUND
    border = _normalize_hex(section.get("border", ""), DEFAULT_BORDER) if hasattr(section, "get") else DEFAULT_BORDER
    error = root / "error.png"

    return Character(
        folder=root,
        name=name,
        icon_path=icon.resolve(),
        thinking_path=thinking.resolve(),
        error_path=error.resolve() if error.exists() else None,
        emotions=emotions,
        background=background,
        border=border,
    )


def load_first_character(search_root: str | Path) -> Character | None:
    root = Path(search_root)
    if not root.exists():
        return None
    for candidate in sorted(path for path in root.iterdir() if path.is_dir()):
        try:
            return load_character(candidate)
        except CharacterLoadError:
            continue
    return None
