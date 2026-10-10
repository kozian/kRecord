# Tasks

## 1. Settings

- [x] 1.1 Add `SettingsStore.showsMenuBarItem` (default on) and bind it to `MenuBarExtra(isInserted:)` (design D1); add "Show in menu bar" to the "Menu Bar" section and disable "Show recording time in menu bar" while it is off; verify with a unit test (default on, persists) and with the DEBUG remote control (`hideMenuBarItem`, `showMenuBarItem`) that the item disappears and comes back when the setting changes (checked by the user on screen: the window server does not list menu bar windows without screen recording access)
- [x] 1.2 Add the note under "Save as m4a" (design D2) and remove the microphone picker from the Settings window (design D3); verify with Settings snapshots in English and Russian, that the window still has no scroll bar, and with `scripts/check-localization.py`

## 2. Main window and About

- [x] 2.1 Label the source checkboxes "Microphone" and "System audio" with Russian translations; verify with main window snapshots in English and Russian
- [x] 2.2 Set the copyright line to "© 2026 Kuznetsov Konstantin" (design D4); verify `NSHumanReadableCopyright` in the built app's Info.plist

## 3. Documentation

- [x] 3.1 Update the QA checklist (labels, Settings contents, "Show in menu bar" on/off, Dock reopen without the item, About author) and map the new scenarios in `docs/spec-coverage.md`; verify each new scenario has a test, harness run, or checklist entry
