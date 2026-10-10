# Changelog

Versions follow semantic versioning; the build number is the git commit count of the release commit.

## 0.4.0 — 2026-10-10

### refine-main-window

- Main window: each source is one row, "☑ Microphone ━━━━" and "☑ System ━━━━" (Russian "Микрофон", "Система"); both meters start at the same x.
- Main window: no title bar. The window buttons stay; the window can be dragged by its background; the space above and below the timer is equal.
- The silent system audio hint gets a "Don't show again" link that turns it off.
- Settings, "Recording" section: a "Warn when a recording has no system audio" toggle, on by default, applies immediately.

## 0.3.0 — 2026-10-10

### polish-settings-and-labels

- Settings: "Save as m4a" gets a note that recordings are otherwise saved as `.aac`.
- Settings: the microphone picker is removed; the microphone is chosen in the main window only.
- Settings, "Menu Bar" section: a new "Show in menu bar" toggle, on by default, that shows or hides the menu bar item immediately. "Show recording time in menu bar" is disabled while the item is hidden.
- Main window: the source checkboxes are labeled "Microphone" and "System audio" (Russian "Микрофон", "Системный звук") instead of "Record microphone" and "Record system audio".
- About window: the copyright line names the author, "© 2026 Kuznetsov Konstantin".

## 0.2.1 — 2026-10-10

### add-release-versioning

- Version numbers follow semantic versioning: the marketing version (`CFBundleShortVersionString`, e.g. `0.2.0`) and a build number (`CFBundleVersion`) that only grows. The build number is the git commit count of the release commit, so each build maps to exactly one commit.
- Both numbers live in `Config/Version.xcconfig` instead of the project file.
- `scripts/release.sh <version>` produces a release in one step: checks for uncommitted changes, runs the tests, sets the version and build number, updates `CHANGELOG.md` from the OpenSpec changes archived since the previous release, builds and verifies the signed Release app, commits "Release <version>", tags `v<version>`, and writes `build/dist/kRecord-<version>.zip` with a SHA-256 checksum. A `--dry-run` mode does everything except the commit and tag.
- First release: 0.2.0.

### fix-device-switching-and-settings-focus

- Echo-cancellation capture follows input device changes like the default capture path does: it falls back to the default input when the selected microphone disappears, uses the selected microphone again when it comes back, follows the macOS default input when "System Default" is selected, and keeps the microphone track aligned with system audio across the switch. A device with another sample rate is converted correctly after the switch.
- "Settings…" in the menu bar menu brings the Settings window to the front, also when another app is active.
- The Settings window is sized to its content and does not scroll, also when the folder notice is shown and in Russian.
- In the main window, a colon follows the microphone symbol before the device picker, so the symbol reads as the picker's label (presentation only; the main-window spec does not describe the symbol).
- The audio-capture, menu-bar, and settings specs state these cases explicitly as scenarios.

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
