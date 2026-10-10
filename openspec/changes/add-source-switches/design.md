# Design

## Context

See proposal.md. Today `RecordingSession.start()` captures `permittedSources` from `PermissionsManager`, `AppModel.canToggleRecording` depends on `permissions.canRecord`, and the capture engines, writer, and finalizer already handle a single source (used when a permission is denied): no microphone device or voice-processing engine is opened without `.microphone`, and in separate-files mode the writer creates only the captured source's stream.

## Goals / Non-Goals

**Goals:**
- Leave a source out of a recording entirely, using the single-source paths that exist.

**Non-Goals:**
- Muting during a recording; per-source gain.

## Decisions

### D1. Two persisted switches in `SettingsStore`
`SettingsStore` gets `recordsMicrophone` and `recordsSystemAudio` (UserDefaults, default `true`), and `RecordingSettings` carries them as `enabledSources: CaptureSources`. They are not shown in the Settings window; their only controls are the checkboxes in the main window.
- **Why:** same persistence and snapshot-at-start rules as the other recording options.

### D2. Sources of a recording
`RecordingSession` captures `permittedSources ∩ settings.enabledSources`. `canStart` and `AppModel.canToggleRecording` require that set to be non-empty. When the microphone is off, `AppModel.startRecording()` does not request microphone access either.
- **Why:** a source that is off never reaches `CaptureConfiguration`, so the engines, writer, and finalizer need no change and the microphone is never opened.
- **Alternative:** capture and write silence — rejected: the microphone must not be opened.

### D3. Checkboxes next to the meters
Each `LabeledLevelMeter` row in the main window gets a leading checkbox (`Toggle` in checkbox style) labelled by the meter caption. Checkboxes are disabled unless the session is idle. When no permitted source is on, the record button is disabled and a short note under it says to turn on a source. New strings get Russian translations.

### D4. Coordination with `add-app-audio-source`
Both changes add controls next to the system audio meter and modify `main-window` and `audio-capture`, but different requirement blocks, so their deltas archive in either order. Whichever is implemented second adapts the meter row layout (checkbox, meter, and the application picker).

## Risks / Trade-offs

- [A user turns a source off, forgets, and records a meeting without it] → The checkbox state is visible next to the meters before every recording; the meter of an off source stays empty while recording.
