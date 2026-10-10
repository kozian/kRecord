# Tasks

## 1. Shared action

- [x] 1.1 Move the reveal logic into `AppModel.revealRecordingsFolder()` with an injectable opener and use it from the Settings window; verify with a unit test (missing folder is created, the opener receives the destination folder)

## 2. Main window

- [x] 2.1 Add the folder and gear icon buttons (borderless, small, square, tooltips, Russian strings) after the microphone picker, enabled during recordings; verify with view snapshots (idle, recording) and `scripts/check-localization.py`
- [x] 2.2 Reduce the main window width (target 300 pt, 310 pt as settled in design D1); verify with English and Russian snapshots of all main window states (idle, recording, banners, both sources off, silent-audio hint) that no text is cut off, and adjust the width in 10 pt steps if needed

## 3. Documentation

- [x] 3.1 Add QA checklist items (folder button opens the recordings folder, gear button opens Settings, both usable while recording, narrow window fits in Russian) and map the new scenarios in `docs/spec-coverage.md`; verify each new scenario has a test or checklist entry
