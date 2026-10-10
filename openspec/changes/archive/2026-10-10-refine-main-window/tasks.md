# Tasks

## 1. Main window

- [x] 1.1 Show each source as one row (design D1) and remove `SourceLevelMeter`; verify main window snapshots in English and Russian (all states) and `scripts/check-localization.py`
- [x] 1.2 Hide the main window's title bar with background dragging and even spacing around the timer (design D3); verify with the DEBUG remote control drawing of the running window (window buttons shown, no title, equal gaps)

## 2. Silent system audio hint

- [x] 2.1 Add `SettingsStore.warnsAboutSilentSystemAudio` (default on), the "Don't show again" link, and the Settings toggle (design D2); verify with unit tests (default, persistence), a view test that the hint disappears when the setting is off, the Settings switch test (seven settings, toggle not locked while recording), and English and Russian snapshots

## 3. Documentation

- [x] 3.1 Update the QA checklist and `docs/spec-coverage.md` for the new and changed scenarios; verify each has a test, harness run, or checklist entry
