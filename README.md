# NativeGemini

NativeGemini is a PySide6/QML desktop overlay for KDE Plasma on Wayland. It gives you a quick Gemini chatroom UI, toggled with a global hotkey, with a persistent character portrait, local chat history, optional web grounding, and screenshot/file context.

The app is built for a local desktop workflow: start it hidden, press `Meta+G`, ask Gemini, then dismiss it with `Esc` or by focusing another app.

## Features

- Global `Meta+G` overlay toggle through the Freedesktop Global Shortcuts portal.
- Frameless, transparent, always-on-top QML overlay.
- Chatrooms with search, rename, delete confirmation, generated titles, and `Ctrl+T` / `Ctrl+W` new-chat shortcuts.
- Gemini model picker populated from the Gemini API.
- Secure Gemini and Tavily API-key storage through the desktop Secret Service.
- Grounding modes: `Auto`, `Always`, and `Off`.
- Tavily fallback when Gemini native grounding hits quota/rate limits.
- Markdown rendering with tables, code blocks, clickable links, selectable message text, and copy buttons.
- Image attachments from file picker or clipboard, up to 10 pending files.
- Text attachments for `.txt`, `.md`, and `.markdown` files.
- Long pasted text is converted into an attachment.
- Character folders with emotion images, a neutral icon, and optional theme metadata.
- Local SQLite persistence for conversations, messages, and estimated usage.

## Install

```bash
python3 -m venv .venv
.venv/bin/python -m pip install -e ".[test]"
```

## Run

Start normally:

```bash
.venv/bin/nativegemini
```

Start hidden:

```bash
.venv/bin/nativegemini --hidden
```

From this workspace, the exact hidden startup command is:

```bash
cd '/home/Pefiye/Documents/ Projects/Personal Projects/NativeGemini'
.venv/bin/nativegemini --hidden
```

## Autostart

The local KDE autostart entry is installed at:

```text
/home/Pefiye/.config/autostart/NativeGemini.desktop
```

It runs the local virtualenv command:

```desktop
Exec=/usr/bin/env bash -lc "cd '/home/Pefiye/Documents/ Projects/Personal Projects/NativeGemini' && exec .venv/bin/nativegemini --hidden"
```

The repo copy is:

```text
packaging/NativeGemini-local-autostart.desktop
```

Remove `/home/Pefiye/.config/autostart/NativeGemini.desktop` to disable login startup.

## First Setup

1. Launch the app with `.venv/bin/nativegemini`.
2. Open Settings.
3. Save a Gemini API key.
4. Refresh Gemini models with the refresh icon beside Settings.
5. Select a model.
6. Optionally save a Tavily API key for web-search fallback.
7. Optionally select a character folder.

API keys are stored in Secret Service only. NativeGemini intentionally does not save API keys as plaintext config.

## Controls

- `Meta+G`: show or hide the overlay.
- `Esc`: close the overlay.
- `Ctrl+T`: create and open a new chatroom.
- `Ctrl+W`: create and open a new chatroom.
- `Shift+Enter`: insert a newline in the composer.
- `Enter`: send the prompt.
- Click an attached image/file chip to remove it before sending.

## Grounding

Grounding is controlled from the globe/search/cloud button beside the composer:

- `Auto`: the app decides whether the prompt needs fresh information. Hardcoded freshness/currentness checks override the model decision.
- `Always`: try grounding for every prompt.
- `Off`: never use grounding.

Grounding first tries Gemini native grounding. If that fails because of quota/rate limits and a Tavily key is saved, NativeGemini tries Tavily search and sends the search context back through the selected Gemini model.

## Attachments

Supported image attachments:

```text
png, jpg, jpeg, webp, heic, heif
```

Supported text attachments:

```text
txt, md, markdown
```

Limits:

- Maximum 10 pending attachments.
- Maximum 18 MB per pending attachment.
- Maximum 512 KB per text attachment.
- Long pasted text over 1800 characters becomes a temporary text attachment.

Image binaries are sent with the prompt but are not stored permanently in the chat database. Stored user messages include an attachment count note instead.

## Character Folders

Minimum structure:

```text
character-name/
  icon.png
  thinking.png
  emotions/
    neutral.png
    confident.png
```

Optional `char.ini`:

```ini
[Character]
Name=Character Name
background=A1FF9E
border=FF8B43
```

Emotion names come from filenames under `emotions/`.

## Local Data

NativeGemini stores local app data under:

```text
~/.config/NativeGemini/
```

Important files:

```text
config.json
nativegemini.sqlite3
```

The SQLite database stores chatrooms, messages, and estimated usage events. It does not store image attachment binaries.

## Development

Run the test suite:

```bash
.venv/bin/pytest
```

Common focused checks used during development:

```bash
.venv/bin/python -m compileall NativeGemini
.venv/bin/pytest tests/test_db.py tests/test_overlay_scroll.py
timeout 5s .venv/bin/nativegemini --hidden
```

The hidden startup check should exit with `124` when stopped by `timeout`; that means the GUI process launched and kept running.

## Wayland Note

NativeGemini uses a frameless `Qt.Tool` overlay with `WindowStaysOnTopHint`. This works well for the desktop overlay workflow, but Wayland compositors may still treat fullscreen windows specially.
