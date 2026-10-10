# Changelog

Versions follow semantic versioning; the build number is the git commit count of the release commit.

## 0.2.0 — 2026-10-10

### add-core-recording

- New native macOS app **kRecord** (macOS 15+, Apple silicon) built only on Apple system frameworks.
- Capture microphone (mono) and all system audio simultaneously, kept in sync on a shared timeline.
- Follow the system default input device; optionally let the user pick a specific microphone, falling back to the default if it disappears.
- Optional echo cancellation (system voice processing) toggle for recording with speakers.
- Save recordings automatically to a configurable folder (default `~/Music/kRecord/`) with timestamp-based file names:
  - default: one mixed stereo file (system audio stereo, microphone centered, 50/50 mix);
  - option: separate microphone and system audio files.
- Recordings are AAC (48 kHz, 128 kbps), encoded live while recording. They are saved as `.m4a` by default (the AAC stream is repackaged on stop, without re-encoding), or kept as the raw `.aac` stream when "Save as m4a" is off.
- Crash-safe recording: the AAC stream is written incrementally, so an interrupted recording remains playable.
- Recording stops with a visible error when disk space runs out or the destination folder becomes unavailable.
- Main window: record/stop button, elapsed time, separate level meters for microphone and system audio, microphone selection.
- Menu bar item: grey icon when idle, red while recording, optional elapsed time next to the icon; menu with Start/Stop Recording, Settings…, Quit. Quitting during a recording asks to confirm "Stop recording and quit".
- Settings window: destination folder, microphone, save as m4a, separate-files option, echo cancellation, show-time-in-menu-bar.
- Request microphone and system audio capture permissions on first launch; record whatever sources are permitted.
- UI localized in English and Russian.
- A manual QA checklist document (Markdown) covering behavior that cannot be unit-tested.

### add-source-switches

- A checkbox next to each level meter in the main window turns the microphone source or the system audio source on or off for the next recording.
- A source that is off is not captured at all: the microphone is not opened (no microphone-in-use indicator), and in separate-files mode no file is created for it.
- The checkboxes can only be changed before a recording starts; they are locked while a recording is active or being saved.
- At least one source that is on and permitted is needed to record; otherwise the record button is disabled.
- Both checkboxes are on by default and are remembered across launches.

### polish-main-window

- The main window becomes narrower, sized to its content, while every text (also in Russian) stays fully visible.
- Two small square icon buttons to the right of the microphone picker: a folder that opens the recordings folder in Finder, and a gear that opens the Settings window. They are deliberately unobtrusive (small, plain icons with tooltips), not prominent controls.
