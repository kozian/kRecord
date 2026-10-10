# Design

## Context

Prototyped in the branch `spike/inline-level-meters` and checked with snapshots of every main window state in English and Russian, and with drawings of the running window including its frame (DEBUG remote control `snapshotMainWindow`). This change moves the accepted spike into the main line.

## Goals / Non-Goals

**Goals:** a more compact main window (one row per source, no title bar) and a way to turn off the silent system audio hint.

**Non-Goals:** other layout changes; changing when the hint is shown.

## Decisions

### D1. One row per source in a `Grid`
Checkbox (with its label) and meter in one `GridRow` per source; the label column is as wide as the longer label, so both meters start at the same x in English and Russian. The labels are the short "Microphone" / "System" ("Микрофон" / "Система"). `SourceLevelMeter` (checkbox above the meter) is removed. The caption font and the 0.4 opacity of a turned-off source's meter are kept.

### D2. Turning the silent audio hint off
`SettingsStore.warnsAboutSilentSystemAudio` (default on when unset). The hint is shown only while it is on. The hint has two link buttons, "Open System Settings" and "Don't show again"; ✕ still hides it until the next recording. The links sit side by side when they fit (English) and one below the other otherwise (Russian, where "Открыть Системные настройки" wrapped and centered) — `ViewThatFits`. The Settings toggle sits in the "Recording" section and is not locked during recordings.

### D3. Main window without title bar
`.windowStyle(.hiddenTitleBar)` and `.windowBackgroundDragBehavior(.enabled)` (macOS 15) on the `Window` scene. SwiftUI keeps the title bar strip as the top safe area, so the content stays below the window buttons; the view drops its own 16 pt top padding and adds 7.5 pt, which makes the gap from the window buttons to the digits equal to the gap from the digits to the record button (27.5 pt each, measured on the window drawing). The window is 271 pt tall instead of 280 pt.
- **Rejected in the spike:** ignoring the top safe area (content under the window buttons) — the digits crowded the buttons and the window kept its height with an empty strip at the bottom.
- **Trade-offs:** double-clicking the top strip still performs the system's title bar double-click action; the window title stays for the Window menu, Mission Control, and accessibility. The Settings window keeps its title bar.

## Risks / Trade-offs

- [The window looks less like a standard document window] → Accepted by the user after trying the spike.
- [A remembered window frame from before the change opens slightly offset once] → Harmless; the next save fixes it.
