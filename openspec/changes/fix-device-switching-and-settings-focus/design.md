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
`VoiceProcessingCaptureEngine` uses a `DeviceMonitor` (device list, default input and output, the current microphone's liveness) and also treats `AVAudioEngineConfigurationChange` of its voice-processing engine as a device change. On each change it resolves the wanted microphone with `AggregateCaptureEngine.resolveInputDevice(selectedUID:)` and rebuilds the microphone path when the wanted device differs from the current one, the current one died, or the voice-processing engine is no longer running. Changes are coalesced by the monitor and handled one at a time on the engine actor.
- **Why:** one rule set for both capture modes; the configuration-change notification alone does not say which device to use.
- **Alternative:** keep relying on the notification and `engine.start()` — that is the current bug.

### D2. Rebuild with a fresh voice-processing engine
A rebuild removes the tap from and stops the old `AVAudioEngine`, then creates a new one: enable voice processing, set the device when it is not the default input, apply the ducking configuration, prepare the converter for the new input format, install the tap, start. The `VoiceMicrophonePath` (ring buffer, frames written, timeline) is kept, so the host-time alignment pads the switch gap with silence and trims overlap. `VoiceMicrophonePath.prepare(inputFormat:)` resets and rebuilds the converter for every new format.
- **Why:** a voice-processing unit keeps its device binding; reconfiguring a live one is unreliable, and creating the engine is how the first start already works.
- **Alternative:** `setDeviceID` on the running engine — not reliable with voice processing enabled.

### D3. Restart the system aggregate after voice processing
Because of the start-order finding (D6 of the archived design), every voice-processing rebuild during a recording is followed by a rebuild of the system aggregate: `AggregateCaptureEngine` gets a method that tears down its IOProc and aggregate and builds them again with the same tap, ring buffers, level snapshot, and timeline anchor. The timeline's frame counter continues, so microphone audio captured during the system gap is trimmed and both tracks lose the same span.
- **Why:** avoids the frame loss of a system aggregate running underneath a voice-processing start.
- **Trade-off:** the system track also gets a short gap (aggregate rebuild, under half a second) on each microphone switch.
- **Verification:** click spacing in the system track after a switch must stay at 1.0 s (the frame-loss symptom was 0.7 s).

### D4. No microphone left
If voice processing cannot start on any candidate (resolved device, default input), the recording continues with system audio only and a silent microphone track; the next device change tries again. At stop, the microphone path pads its ring up to the system timeline's frame count so separate microphone and system files end together, as they do in the default path. A `.inputDeviceChanged` event is emitted whenever a different microphone is in use.
- **Why:** matches the default path's fallback and the spec scenario; a failed microphone must not end the recording.

### D5. "Settings…" as a button that activates the app
The menu item becomes a `Button` that calls `NSApp.activate()` and then the SwiftUI `openSettings` environment action (macOS 14+), replacing `SettingsLink` and its gesture.
- **Why:** in a `.menu`-style `MenuBarExtra` items are AppKit menu items, so gestures attached to them never run; a button action does.
- **Alternative:** activating in the Settings view's `onAppear` — does not help when the Settings window is already open behind another app.

### D6. Settings window sized to its content, scrolling off
The form gets `.scrollDisabled(true)` and the `Settings` scene `.windowResizability(.contentSize)`, so the window height follows the form's content, including the folder notice and longer Russian text. If the grouped form's ideal height still differs from its content, the form is measured from its content instead (for example with a non-scrolling `VStack`-based layout in the same grouped style).
- **Why:** nothing in the window needs scrolling; six settings always fit on screen.
- **Alternative:** a larger fixed height — breaks again when the notice or translations change the content height.
- **Verification:** the DEBUG remote control logs, for the open Settings window, whether its scroll view shows a scroller and the document height against the visible height, in English and Russian, with and without the folder notice.

## Risks / Trade-offs

- [A microphone switch with echo cancellation takes about as long as a voice-processing start, so the microphone track has a gap of roughly a second] → Padded with silence and aligned; accepted for the opt-in mode.
- [Device events arrive in bursts (unplugging a USB device changes the list and the default input)] → The monitor coalesces them; the engine compares the wanted device with the current one before rebuilding, so a burst causes one rebuild.
- [Disabling scrolling hides content on a very small screen] → The window is about 520 pt tall; every supported Mac screen fits it.
- [The fix cannot be fully tested without unplugging hardware] → Default-input changes are tested with the debug harness (switching the default input to another device); unplugging and reconnecting the selected microphone is a manual QA item, as is the menu item.
