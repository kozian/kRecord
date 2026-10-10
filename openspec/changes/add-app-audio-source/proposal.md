# Proposal

## Why

kRecord records all system audio, so notifications, music, and other apps end up in a meeting recording. Users want to record just the meeting app (Zoom, a browser with Meet, Telegram).

## What Changes

- New choice of the system audio source: "All Audio" (always the first option and the default) or one application. Only that application's audio, including audio its helper processes play (for example a browser's tabs), is recorded as system audio.
- If the selected application is not running when a recording starts, or quits during a recording, the recording continues with a silent system audio track and picks the application up as soon as it starts again. The picker shows it as "<name> (not running)".
- The system audio source is chosen in the main window (next to the system audio meter) and in the Settings window, like the microphone, and is remembered across launches. It cannot be changed during a recording.
- Works on macOS 15 and later: the application's processes are tracked by kRecord itself, not with the macOS 26-only tap features.

Out of scope: recording several selected apps at once, excluding apps from "All Audio", turning sources off (change `add-source-switches`).

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `audio-capture`: the system audio source can be one application instead of all audio (requirement renamed from "All system audio is captured"); behavior when that application is not running or restarts.
- `main-window`: system audio source picker.
- `settings`: the system audio source is a setting with default "All Audio", shown in the Settings window and locked during a recording.

## Impact

- Capture: `kRecord/Audio/AggregateCaptureEngine.swift` (per-application process tap, tracking the application's processes during a recording), `VoiceProcessingCaptureEngine.swift` (same system source), `CaptureEngine.swift` (configuration of the system source), new application catalog next to `AudioDeviceCatalog`.
- Settings: `SettingsStore`, `RecordingSettings`.
- UI: `MainWindowView`, `SettingsView`, an application picker next to `MicrophonePicker`, the silent-audio hint text, `Localizable.xcstrings` (Russian).
- Tests, the DEBUG recording harness (source flag), `docs/manual-qa-checklist.md`, `docs/spec-coverage.md`.
- The open change `fix-device-switching-and-settings-focus` also modifies the settings requirement "Available settings"; see the design for the order of archiving.
