# Proposal

## Why

Small wording and layout fixes after using 0.2.1. "Save as m4a" does not say what happens when it is off. The microphone picker exists twice, in the main window and in Settings. The menu bar item cannot be turned off. The source checkboxes repeat "Record" in front of both sources. And the About window does not name the author.

## What Changes

- Settings: "Save as m4a" gets a note that recordings are otherwise saved as `.aac`.
- Settings: the microphone picker is removed; the microphone is chosen in the main window only.
- Settings, "Menu Bar" section: a new "Show in menu bar" toggle, on by default, that shows or hides the menu bar item immediately. "Show recording time in menu bar" is disabled while the item is hidden.
- Main window: the source checkboxes are labeled "Microphone" and "System audio" (Russian "Микрофон", "Системный звук") instead of "Record microphone" and "Record system audio".
- About window: the copyright line names the author, "© 2026 Kuznetsov Konstantin".

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `settings`: "Available settings" (no microphone, new "Show in menu bar", note under "Save as m4a"), "Default values" (show in menu bar on), "Settings apply to next recording" (menu bar settings apply immediately).
- `main-window`: "Microphone picker" is replaced by "Microphone choice" (the picker exists only in the main window); "Source checkboxes" (labels).
- `menu-bar`: "Menu bar item always present" becomes a menu bar item shown while the setting is on.

The About window's copyright line is standard app metadata and is not described in the specs.

## Impact

- `kRecord/Views/SettingsView.swift`, `kRecord/Views/MainWindowView.swift`, `kRecord/KRecordApp.swift` (`MenuBarExtra(isInserted:)`), `kRecord/Settings/SettingsStore.swift` (new `showsMenuBarItem`).
- `kRecord/Localizable.xcstrings`: new and removed strings.
- `kRecord.xcodeproj/project.pbxproj`: `INFOPLIST_KEY_NSHumanReadableCopyright`.
- Tests (settings defaults, snapshots), `docs/manual-qa-checklist.md`, `docs/spec-coverage.md`.
