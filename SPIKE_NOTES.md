# NativeGemini Spike Notes

Date: 2026-08-21

## Environment

- OS: Fedora Linux 44 KDE Plasma Desktop Edition
- Session: Wayland
- KWin: 6.7.4
- `org.freedesktop.portal.Desktop`: present on the user bus
- `org.freedesktop.portal.GlobalShortcuts`: present, version 2
- Introspected signatures:
  - `CreateSession(a{sv}) -> o`
  - `BindShortcuts(oa(sa{sv})sa{sv}) -> o`
  - `Activated(o s t a{sv})`

## Layer-Shell Decision

No Python-accessible LayerShellQt binding was available at the start of implementation. The app currently uses the planned fallback:

- `Qt.Tool`
- `Qt.FramelessWindowHint`
- `Qt.WindowStaysOnTopHint`
- transparent QQuickView sized to the active screen geometry

Known limitation: this fallback should not be trusted to overlay exclusive fullscreen apps. For the quick desktop/sidebar use case it is the right first runnable baseline.

## Security Decision

The user chose safety as the priority for API-key handling. The app stores the Gemini key through the desktop Secret Service (`org.freedesktop.secrets`) via `secretstorage`. There is no silent plaintext fallback.
