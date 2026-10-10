# Proposal

## Why

Sometimes only one side of a call should be recorded, for example just the remote participants without the user's microphone, or a voice note without anything the Mac plays. Today kRecord always records every permitted source, and the only way to leave one out is to revoke its permission.

## What Changes

- A checkbox next to each level meter in the main window turns the microphone source or the system audio source on or off for the next recording.
- A source that is off is not captured at all: the microphone is not opened (no microphone-in-use indicator), and in separate-files mode no file is created for it.
- The checkboxes can only be changed before a recording starts; they are locked while a recording is active or being saved.
- At least one source that is on and permitted is needed to record; otherwise the record button is disabled.
- Both checkboxes are on by default and are remembered across launches.

Out of scope: muting a source during a recording, per-source volume, choosing which application is recorded (change `add-app-audio-source`).

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `audio-capture`: sources can be turned off; recording with a single source also covers a source that is turned off.
- `main-window`: checkbox per source next to its level meter; record button disabled when no permitted source is on.
- `recording-output`: in separate-files mode only the files of recorded sources are created.

## Impact

- `SettingsStore`, `RecordingSettings` (two switches), `RecordingSession` (sources = switched on ∩ permitted), `AppModel` (`canToggleRecording`).
- `MainWindowView` (checkboxes next to the meters), `Localizable.xcstrings` (Russian).
- The DEBUG recording harness already takes `-KRDebugSources`; no capture-engine change is needed because a source that is off never reaches the capture configuration.
- Tests, `docs/manual-qa-checklist.md`, `docs/spec-coverage.md`.
