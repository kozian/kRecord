# Design

## Context

`SettingsView` is a grouped `Form` sized to its content (archived fix-device-switching design D6). The menu bar item is a `MenuBarExtra` scene in `KRecordApp`; the app has a regular activation policy, a Dock icon, and `applicationShouldHandleReopen` returns `true`, so a Dock click reopens the main window. `MicrophonePicker` is shared by the main window and Settings.

## Goals / Non-Goals

**Goals:** the five small changes in the proposal, with English and Russian text.

**Non-Goals:** any change to recording behavior or to the main window layout beyond the checkbox labels.

## Decisions

### D1. Menu bar item through `MenuBarExtra(isInserted:)`
A new `SettingsStore.showsMenuBarItem` (key `showsMenuBarItem`, default `true` when unset, like the source switches) drives `MenuBarExtra(isInserted:)`. SwiftUI removes and re-adds the status item when the binding changes, so the setting applies immediately.
- **Implementation findings:** the scene body of `App` does not track the `@Observable` store, so a binding to `model.settings.showsMenuBarItem` never re-inserted or removed the item; the scene uses `@AppStorage` on the same `UserDefaults` key instead, which updates scenes when the value changes. A first binding that stored every value SwiftUI wrote back looped scene updates at 100% CPU. Consequence: removing the item by ⌘-drag updates the stored value, but an already open Settings window shows the change only after it is reopened.
- **Why:** the documented way to make a `MenuBarExtra` optional; no AppKit status item code.
- **Alternative:** hiding the label content — leaves an empty, clickable status item.
- `isInserted` is also set to `false` by macOS when the user removes the item by ⌘-dragging it out of the menu bar; the binding writes that back to the setting, which is the expected result.

### D2. Note under "Save as m4a"
A caption under the toggle, styled like the existing echo cancellation note: "Otherwise recordings are saved as .aac." / "Иначе записи сохраняются в формате .aac."

### D3. Microphone picker only in the main window
`SettingsView` drops `MicrophonePicker`. `MicrophonePicker` stays a separate view (used once) because it holds the unavailable-device logic.

### D4. Author in About
`INFOPLIST_KEY_NSHumanReadableCopyright = "© 2026 Kuznetsov Konstantin"` in both configurations of the app target; the standard About panel shows it under the version. Not localized: it is a name.

## Risks / Trade-offs

- [With the item hidden and the main window closed the app has no visible window] → The Dock icon reopens the main window (spec scenario); the Settings toggle turns the item back on.
