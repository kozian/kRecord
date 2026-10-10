# Tasks

## 1. Model and session

- [x] 1.1 Add `recordsMicrophone` and `recordsSystemAudio` (default on, persisted) to `SettingsStore` and `enabledSources` to `RecordingSettings`; verify with unit tests for defaults, persistence, and the snapshot
- [x] 1.2 Make `RecordingSession` capture `permittedSources ∩ enabledSources`, require a non-empty set in `canStart` and `AppModel.canToggleRecording`, and skip the microphone request when the microphone is off; verify with unit tests (microphone off → system only in the capture configuration and no microphone request; system off → microphone only; both off → cannot start; separate files with the microphone off → one stream)

## 2. Interface

- [x] 2.1 Add a checkbox to each level meter row in the main window, disabled unless idle, and the note under the record button when no permitted source is on; add Russian strings; verify with view snapshots (both on, microphone off, both off, recording) in English and Russian and `scripts/check-localization.py`
- [x] 2.2 Verify on hardware with the app: with the microphone checkbox off, a recording shows no microphone-in-use indicator and produces only the system file in separate-files mode; with the system audio checkbox off, only the microphone is recorded

## 3. Documentation

- [x] 3.1 Add QA checklist items (microphone off without in-use indicator, system audio off, both off, state remembered, locked during recording, separate files with one source) and map every new scenario in `docs/spec-coverage.md`; verify each new spec scenario has a test or checklist entry
