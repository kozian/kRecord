# Proposal

## Why

The main window is 360 pt wide, more than its content needs, and it has no direct way to reach the recordings or the settings: users go through the menu bar menu or the app menu for Settings and through Finder for the files they just recorded.

## What Changes

- The main window becomes narrower, sized to its content, while every text (also in Russian) stays fully visible.
- Two small square icon buttons to the right of the microphone picker: a folder that opens the recordings folder in Finder, and a gear that opens the Settings window. They are deliberately unobtrusive (small, plain icons with tooltips), not prominent controls.

Out of scope: other layout changes, a list of recordings.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `main-window`: buttons that open the recordings folder and the Settings window.

## Impact

- `kRecord/Views/MainWindowView.swift` (width, microphone row with the two buttons), `kRecord/Views/SettingsView.swift` (reveal action shared with the main window), `kRecord/App/AppModel.swift` (reveal action).
- `Localizable.xcstrings` (tooltips and accessibility labels, Russian), view snapshot tests, `docs/manual-qa-checklist.md`, `docs/spec-coverage.md`.
- The pending change `add-app-audio-source` adds a system audio source picker to the same window; its layout follows the narrower width.
