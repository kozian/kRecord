# Proposal

## Why

I need a dead-simple way to record meetings on my Mac: my own voice from the microphone together with the other participants coming through system audio, saved to a file without any manual post-processing. Existing tools are either heavyweight, require screen-recording permission, or need virtual audio drivers. macOS 15 provides native APIs (Core Audio process taps) that make a lightweight, dependency-free recorder possible.

## What Changes

- New native macOS app **kRecord** (macOS 15+, Apple silicon) built only on Apple system frameworks.
- Capture microphone (mono) and all system audio simultaneously, kept in sync on a shared timeline.
- Follow the system default input device; optionally let the user pick a specific microphone, falling back to the default if it disappears.
- Optional echo cancellation (system voice processing) toggle for recording with speakers.
- Save recordings automatically to a configurable folder (default `~/Music/kRecord/`) with timestamp-based file names:
  - default: one mixed stereo file (system audio stereo, microphone centered, 50/50 mix);
  - option: separate microphone and system audio files.
- Output formats: AAC (`.m4a`, default), ALAC (`.m4a`), WAV.
- Crash-safe recording: audio is written incrementally so an interrupted recording remains readable.
- Recording stops with a visible error when disk space runs out or the destination folder becomes unavailable.
- Main window: record/stop button, elapsed time, separate level meters for microphone and system audio, microphone selection.
- Menu bar item: grey icon when idle, red while recording, optional elapsed time next to the icon; menu with Start/Stop Recording, Settings…, Quit. Quitting during a recording asks to confirm "Stop recording and quit".
- Settings window: destination folder, microphone, output format, separate-files option, echo cancellation, show-time-in-menu-bar.
- Request microphone and system audio capture permissions on first launch; record whatever sources are permitted.
- UI localized in English and Russian.
- A manual QA checklist document (Markdown) covering behavior that cannot be unit-tested.

**Out of scope:** transcription, playback, editing or managing recordings, per-app audio selection, excluding specific sounds, pause/resume, hotkeys, notifications, launch at login, auto-split or auto-stop, quality presets, distribution/notarization, auto-update.

## Capabilities

### New Capabilities
- `audio-capture`: capturing microphone and system audio, input device selection and fallback, stream synchronization, echo cancellation, live level metering.
- `recording-output`: writing recordings to disk: formats, mixing vs. separate files, naming, destination folder, crash safety, disk/folder error handling.
- `recording-session`: the recording lifecycle shared by all UI surfaces: start/stop, elapsed time, error states, quit-while-recording confirmation.
- `main-window`: the primary app window with record button, timer, level meters, and microphone picker.
- `menu-bar`: menu bar status item with recording indicator, optional timer, and menu actions.
- `settings`: user preferences, their defaults, persistence, and the settings window.
- `permissions`: requesting and handling microphone and system audio capture permissions.

### Modified Capabilities
<!-- None: this is the first change in the project. -->

## Impact

- New Xcode project (SwiftUI app target + unit test target), no third-party dependencies.
- Entitlements: App Sandbox, audio input, user-selected file read/write; Info.plist usage descriptions for microphone and system audio capture.
- Requires macOS 15+ on Apple silicon.
- New documentation: manual QA checklist in `docs/`.
