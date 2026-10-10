# Proposal

## Why

Tried in a spike (`spike/inline-level-meters`) and accepted: the main window takes less space and looks calmer when each source is one row and the window has no title bar, and the hint about silent system audio, useful as a check, becomes a nuisance once the user knows why system audio is silent (for example when they only record calls without playback) and needs a way to turn it off.

## What Changes

- Main window: each source is one row, "☑ Microphone ━━━━" and "☑ System ━━━━" (Russian "Микрофон", "Система"); both meters start at the same x.
- Main window: no title bar. The window buttons stay; the window can be dragged by its background; the space above and below the timer is equal.
- The silent system audio hint gets a "Don't show again" link that turns it off.
- Settings, "Recording" section: a "Warn when a recording has no system audio" toggle, on by default, applies immediately.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `main-window`: "Source checkboxes" (one row with the meter, labels "Microphone" and "System"); new "Window without title bar".
- `permissions`: "Unknown system audio permission status" (hint can be turned off).
- `settings`: "Available settings", "Default values", "Settings apply to next recording" (the warning toggle).

## Impact

- `kRecord/Views/MainWindowView.swift`, `kRecord/Views/LevelMeter.swift` (`SourceLevelMeter` removed), `kRecord/Views/SettingsView.swift`, `kRecord/KRecordApp.swift`, `kRecord/Settings/SettingsStore.swift`, `kRecord/Localizable.xcstrings`.
- DEBUG remote control: `snapshotMainWindow` draws the main window with its frame into `~/Music/kRecord/main-window.png`.
- Tests, `docs/manual-qa-checklist.md`, `docs/spec-coverage.md`.
