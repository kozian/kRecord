# Design

## Context

`MainWindowView` is a `VStack` padded by 20 pt and fixed to 360 pt wide. The microphone row is `LabeledContent("Microphone") { MicrophonePicker … }`. The Settings window reveals the destination folder with a private `revealFolder()` (create the folder if needed, then `NSWorkspace.open`).

## Goals / Non-Goals

**Goals:**
- A width that fits the content in English and Russian without wasted space.
- Two quiet icon buttons, consistent with macOS small controls.

**Non-Goals:**
- Reworking the rest of the layout.

## Decisions

### D1. Width 300 pt, verified in Russian
The fixed width drops from 360 to 300 pt (260 pt of content). The microphone row then holds the "Microphone" label, the picker (which truncates long device names on its own), and two 22 pt buttons; the timer, record button, meters, and banners wrap or fit within 260 pt. The width is checked with Russian snapshots ("Системный по умолчанию" is the longest default text); if anything is cut, the width grows in steps of 10 pt rather than shortening translations.
- **Alternative:** no fixed width (fit to content) — the window would change width when banners appear or devices change.

### D2. Icon buttons
`Button` with `Image(systemName: "folder")` and `Image(systemName: "gearshape")`, `.buttonStyle(.borderless)`, small control size, a square 22 × 22 pt hit area, `.help` tooltips ("Show Recordings in Finder", "Settings") that double as accessibility labels. They sit after the picker in the microphone row and are not disabled during a recording.
- **Why borderless:** keeps them quiet next to the picker, as requested; the square hit area keeps them easy to click.

### D3. Shared actions
`AppModel.revealRecordingsFolder()` (create the folder if missing, then open it via an injectable opener, default `NSWorkspace.open`) is used by both the Settings window and the main window. The gear button uses SwiftUI's `openSettings` environment action, as the menu bar fix in `fix-device-switching-and-settings-focus` will.

## Risks / Trade-offs

- [Long microphone names get truncated in the narrower picker] → The picker shows the full name in its menu; truncation in the closed state is normal for macOS pop-up buttons.
