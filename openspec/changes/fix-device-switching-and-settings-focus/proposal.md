# Proposal

## Why

Checking the code of `add-core-recording` against its specs, and using the app, found three places where it does not behave as intended. With echo cancellation on, the microphone does not follow device changes: an unplugged selected microphone leaves the microphone track silent for the rest of the recording instead of falling back to the default input. "Settings…" in the menu bar menu can open the Settings window behind the app the user is working in. And the Settings window opens scrollable, with a scroll bar, although all settings fit and are shown.

## What Changes

- Echo-cancellation capture follows input device changes like the default capture path does: it falls back to the default input when the selected microphone disappears, uses the selected microphone again when it comes back, follows the macOS default input when "System Default" is selected, and keeps the microphone track aligned with system audio across the switch. A device with another sample rate is converted correctly after the switch.
- "Settings…" in the menu bar menu brings the Settings window to the front, also when another app is active.
- The Settings window is sized to its content and does not scroll, also when the folder notice is shown and in Russian.
- The audio-capture, menu-bar, and settings specs state these cases explicitly as scenarios.

Out of scope: faster start with echo cancellation (prewarming voice processing), any other behavior change.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `audio-capture`: "Default input device is followed" and "Fallback when selected microphone disappears" apply with echo cancellation on as well; scenarios added for that mode.
- `menu-bar`: "Settings from menu" brings the window to the front even when another app is active; scenario added.
- `settings`: "Available settings" shows all settings without scrolling; scenario added.

## Impact

- `kRecord/Audio/VoiceProcessingCaptureEngine.swift`: device monitoring and rebuilding of the voice-processing microphone path during a recording; `VoiceMicrophonePath` converter set up per device format.
- `kRecord/Audio/AggregateCaptureEngine.swift`: a way to rebuild the system-audio aggregate after voice processing restarts (D6 of the archived add-core-recording design requires voice processing to start first).
- `kRecord/Views/MenuBar.swift`: the "Settings…" item.
- `kRecord/Views/SettingsView.swift` and the `Settings` scene in `kRecord/KRecordApp.swift`: sizing of the Settings window.
- Tests, the DEBUG harness if needed for verification, and `docs/manual-qa-checklist.md`.
