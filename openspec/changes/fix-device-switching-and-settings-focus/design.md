# Design

## Context

See proposal.md for the two bugs. Constraints from the archived design of `add-core-recording` (`openspec/changes/archive/2026-10-10-add-core-recording/design.md`):

- D3: the default capture path (`AggregateCaptureEngine`) follows device changes with a `DeviceMonitor` and rebuilds its aggregate, trying the resolved device, then the default input, then no microphone (silent, aligned microphone track).
- D6: echo cancellation records the microphone through `AVAudioEngine` with voice processing and system audio through a tap-only aggregate. Voice processing must start *before* the system aggregate: started under a running aggregate it reconfigures the output device and the system track loses about 30% of its frames. Microphone buffers are placed on the system timeline by host time (`TimelineAnchor`, `MicAlignment`), which trims or pads them.

The Settings window is a `Form` with `.formStyle(.grouped)`, fixed to 480 pt wide and `.fixedSize(horizontal: false, vertical: true)`. A grouped form is a scroll view; the window takes its height from the form's ideal height, which comes out slightly smaller than the laid-out content, so the window opens with a scroll bar.

Today `VoiceProcessingCaptureEngine` binds a selected microphone once with `auAudioUnit.setDeviceID`, sets up the sample-rate converter once, and on `AVAudioEngineConfigurationChange` only calls `engine.start()` again on the same engine.

## Goals / Non-Goals

**Goals:**
- Echo-cancellation capture switches microphones with the same rules as the default path and keeps both tracks aligned and complete.
- "Settings…" in the menu bar menu activates the app and shows the Settings window in front.
- The Settings window fits its content exactly, without scrolling, and grows when the folder notice appears.

**Non-Goals:**
- Making the switch gap shorter than the voice-processing start time (about a second); prewarming is a separate change.
- Changing the default capture path.

## Decisions

### D1. Watch devices the same way as the default path
`VoiceProcessingCaptureEngine` uses a `DeviceMonitor` (device list, default input and output, the current microphone's liveness) and also treats `AVAudioEngineConfigurationChange` of its voice-processing engine as a device change. On each change it resolves the wanted microphone with `AggregateCaptureEngine.resolveInputDevice(selectedUID:)` and rebuilds the microphone path when the wanted device differs from the one the last rebuild aimed for, the current one died, or the voice-processing engine is no longer running. Changes are coalesced by the monitor and handled one at a time on the engine actor, without suspending; changes during `start` are ignored and one check runs when `start` finishes.
- **Implementation finding:** voice processing on a device that is not the default input stops its engine right after starting (a configuration change it causes itself). A full rebuild there cost 1.4 s at every start; when the wanted device is unchanged and alive, the engine is first simply restarted (0.07 s), and only rebuilt if that fails. Comparing with the device the last rebuild *aimed for* (not the one in use) keeps a failed device from being retried on every unrelated change, e.g. when kRecord's own aggregates appear in the device list.
- **Why:** one rule set for both capture modes; the configuration-change notification alone does not say which device to use.
- **Alternative:** keep relying on the notification and `engine.start()` — that is the current bug.

### D2. Rebuild with a fresh voice-processing engine
A rebuild removes the tap from and stops the old `AVAudioEngine`, then creates a new one: enable voice processing, set the device when it is not the default input, apply the ducking configuration, prepare the converter for the new input format, install the tap, start. The `VoiceMicrophonePath` (ring buffer, frames written, timeline) is kept, so the host-time alignment pads the switch gap with silence and trims overlap. `VoiceMicrophonePath.prepare(inputFormat:)` resets and rebuilds the converter for every new format.
- **Why:** a voice-processing unit keeps its device binding; reconfiguring a live one is unreliable, and creating the engine is how the first start already works.
- **Alternative:** `setDeviceID` on the running engine — not reliable with voice processing enabled.

### D3. Keep the system aggregate running; rebuild it only when it stalls
The plan was to rebuild the system aggregate after every voice-processing rebuild, because of the start-order finding (D6 of the archived design). Measured on hardware, that made things worse: a voice-processing restart under the running aggregate costs about 0.1 s of system audio once (one click interval of 0.89–0.92 s, then 1.0 s spacing again for 20 s, no continuous frame loss), while a rebuild of the aggregate costs about 0.86 s per switch (the rebuild calls take 0.12 s; the rest is the tap starting to deliver again). So a microphone switch leaves the system aggregate alone.
One case does need it: when the last input device disappears under voice processing (a Mac mini without a built-in microphone, USB microphone unplugged), the system aggregate stops delivering until voice processing starts again, which lost the whole 12.5 s the microphone was unplugged. A supervision task (every 250 ms) watches the system timeline; when it has not advanced for 0.5 s, `AggregateCaptureEngine.rebuildDevice()` tears down the IOProc and aggregate and builds them again with the same tap, ring buffers, level snapshot, and timeline anchor, so the tracks continue where they stopped.
- **Measured:** unplugging the last microphone loses 1.1–1.4 s of system audio (detection plus rebuild; 1.9 s with a 1 s threshold), plugging it back in 0.4 s.

### D4. No microphone left
If voice processing cannot start on any candidate (resolved device, default input), the recording continues with system audio only and a silent microphone track; a later change of the wanted device tries again. While there is no microphone, the supervision task pads the microphone ring up to the system timeline every 250 ms: the mixed writer advances both tracks together, so without it the system ring (10 s) would overflow. At stop, the microphone path pads its ring the same way so separate microphone and system files end together, as they do in the default path. A `.inputDeviceChanged` event is emitted whenever a different microphone is in use. Microphone-only capture with no microphone left fails with `.failed`.
- **Why:** matches the default path's fallback and the spec scenario; a failed microphone must not end the recording.

### D5. "Settings…" as a button that activates the app
The menu item becomes a `Button` that calls the SwiftUI `openSettings` environment action (macOS 14+), replacing `SettingsLink` and its gesture, and then, on the next run loop pass, activates the app with `NSApp.activate(ignoringOtherApps: true)` and orders the Settings window front (`makeKeyAndOrderFront`, `orderFrontRegardless`). The same `SettingsWindow.show` helper is reachable from the DEBUG remote control (`openSettingsLikeMenuBar`), whose `logState` reports the active app and the topmost window.
- **Why:** in a `.menu`-style `MenuBarExtra` items are AppKit menu items, so gestures attached to them never run; a button action does. The cooperative `NSApp.activate()` is declined while another app is active: with Finder active, the window opened behind Finder (first implementation, reported by the user and reproduced with the remote control); the forced activation makes kRecord active with the Settings window key and topmost.
- **Alternative:** activating in the Settings view's `onAppear` — does not help when the Settings window is already open behind another app.

### D6. Settings window sized to its content, scrolling off
The form gets `.scrollDisabled(true)` and the `Settings` scene `.windowResizability(.contentSize)`, so the window height follows the form's content, including the folder notice and longer Russian text. If the grouped form's ideal height still differs from its content, the form is measured from its content instead (for example with a non-scrolling `VStack`-based layout in the same grouped style).
- **Why:** nothing in the window needs scrolling; six settings always fit on screen.
- **Alternative:** a larger fixed height — breaks again when the notice or translations change the content height.
- **Verification:** the DEBUG remote control logs, for the open Settings window, whether its scroll view shows a scroller and the document height against the visible height, in English and Russian, with and without the folder notice.

### D7. Microphone label and picker in the main window
In the main window the microphone symbol before the device picker is followed by a colon ("🎤:"), so it reads as a label of the picker. The colon is part of the hidden, secondary-styled label; the picker's accessibility label stays "Microphone". The picker follows 4 pt after the label and is aligned to the leading edge; the free space goes between it and the buttons.
- **Why:** a SwiftUI menu picker on macOS is never wider than its longest item: neither `maxWidth: .infinity` nor a fixed `frame(width:)` widens it, and a `Menu` sizes to its label the same way. Centered in the row, its side gaps changed with the connected devices' names (first implementation, reported by the user); leading alignment keeps the gap after the label constant.
- **Alternative:** an `NSPopUpButton` wrapped for SwiftUI would fill the row at a fixed width; not worth the extra control for this.

## Hardware results (Mac mini, Razer Seiren V3 Mini, echo cancellation on, separate files, clicks played through the speakers)

| Case | Track lengths | System audio lost | Strong clicks, mic after system |
|---|---|---|---|
| Default input switched three times (to a test aggregate on the same microphone and back), 40 s | equal | 0.10–0.20 s per switch, 1.0 s spacing otherwise | 7.5–7.8 ms before and after |
| Selected device removed, fallback to the default input | equal | 0.08 s | 7.2–7.3 ms |
| Selected USB microphone unplugged (no input left) and plugged back in | equal | 1.1–1.4 s at unplug, 0.4 s at replug | 6.6–7.4 ms before, 4.8–5.0 ms after |

## Risks / Trade-offs

- [A microphone switch with echo cancellation takes about as long as a voice-processing start, so the microphone track has a gap of roughly a second] → Padded with silence and aligned; accepted for the opt-in mode.
- [The stall watchdog rebuilds the system aggregate when nothing arrives for 0.5 s, also if the cause is something else] → System audio normally arrives every few milliseconds (the keep-alive output keeps the tap running), so a false positive costs one rebuild of about 0.9 s.
- [Device events arrive in bursts (unplugging a USB device changes the list and the default input)] → The monitor coalesces them; the engine compares the wanted device with the current one before rebuilding, so a burst causes one rebuild.
- [Disabling scrolling hides content on a very small screen] → The window is about 520 pt tall; every supported Mac screen fits it.
- [The fix cannot be fully tested without unplugging hardware] → Default-input changes are tested with the debug harness (switching the default input to another device); unplugging and reconnecting the selected microphone is a manual QA item, as is the menu item.
