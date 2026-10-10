# Proposal

## Why

kRecord records all system audio, so notifications, music, and other apps end up in a meeting recording. Users want to record just the meeting app (Zoom, a browser with Meet, Telegram) and to leave out a source entirely, for example to record only the remote side without their own microphone.

## What Changes

- New choice of the system audio source: "All Audio" (always the first option and the default) or one application. Only that application's audio, including audio its helper processes play (for example a browser's tabs), is recorded as system audio.
- If the selected application is not running when a recording starts, or quits during a recording, the recording continues with a silent system audio track and picks the application up as soon as it starts again. The picker shows it as "<name> (not running)".
- A checkbox next to each level meter in the main window turns the microphone or system audio source on or off. A source that is off is not captured at all: the microphone is not opened, and in separate-files mode no file is created for it. The checkboxes can only be changed before a recording starts; at least one source must be on to record.
- The system audio source is chosen in the main window (next to the system audio meter) and in the Settings window, like the microphone. The source choice and checkbox states are remembered across launches.
- Works on macOS 15 and later: the app's processes are tracked by kRecord itself, not with the macOS 26-only tap features.

Out of scope: recording several selected apps at once, excluding apps from "All Audio", per-source volume, changing sources during a recording.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `audio-capture`: the system audio source can be one application instead of all audio (requirement renamed from "All system audio is captured"); behavior when that application is not running or restarts; sources can be turned off; recording with a single source also covers a source turned off.
- `main-window`: checkbox per source next to its level meter; system audio source picker; record button disabled when no permitted source is turned on.
- `settings`: the system audio source is a setting with default "All Audio"; source checkbox states have defaults (both on); both are locked during a recording.
- `recording-output`: in separate-files mode only the files of recorded sources are created.

## Impact

- Capture: `kRecord/Audio/AggregateCaptureEngine.swift` (per-application process tap, tracking the application's processes during a recording), `VoiceProcessingCaptureEngine.swift` (same system source), `CaptureEngine.swift` (configuration of the system source), new application catalog (running apps and their audio processes) next to `AudioDeviceCatalog`.
- Settings and session: `SettingsStore`, `RecordingSettings`, `RecordingSession` (sources = turned on ∩ permitted), `AppModel`.
- UI: `MainWindowView`, `SettingsView`, `MicrophonePicker` neighbour for applications, `Localizable.xcstrings` (Russian).
- Tests, the DEBUG recording harness (source flags), `docs/manual-qa-checklist.md`, `docs/spec-coverage.md`.
- The open change `fix-device-switching-and-settings-focus` also modifies the settings requirement "Available settings"; see the design for the order of archiving.
