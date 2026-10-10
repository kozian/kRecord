# Design

## Context

Greenfield project: the repository contains only OpenSpec scaffolding. See `proposal.md` for motivation and scope, and `specs/` for the behavior contract.

Constraints that shape the design:
- macOS 15+, Apple silicon only; Xcode 27 (macOS 27 SDK), Swift 6 strict concurrency, SwiftUI.
- Apple frameworks only (Core Audio, AudioToolbox, AVFoundation, SwiftUI, AppKit where SwiftUI lacks an API). No third-party packages.
- App Sandbox enabled.
- Audio I/O callbacks run on a real-time thread: no allocation, locks, file I/O, or actor hops inside them.

## Goals / Non-Goals

**Goals:**
- One capture pipeline that gives sample-aligned microphone and system audio, so mixing and separate files share the same code path.
- Crash-safe on-disk format during recording, with format conversion deferred to stop.
- A testable core: recording state machine, file naming, settings, mixing math, and finalization run without real audio hardware.

**Non-Goals:**
- Per-process tap filtering, exclusion of the app's own audio or system alert sounds (the app plays no audio of its own).
- Low-latency monitoring or playback.
- Supporting Intel Macs or macOS versions older than 15.

## Decisions

### D1. System audio via Core Audio process tap, not ScreenCaptureKit
Use a `CATapDescription` configured as a global stereo mixdown of all processes, with an empty exclusion list, created via `AudioHardwareCreateProcessTap`.
- **Why:** needs only the "System Audio Recording" privacy permission (`NSAudioCaptureUsageDescription`), not Screen Recording; delivers audio regardless of which output device is active; can later be narrowed to specific processes for the per-app feature without changing the pipeline.
- **Alternatives:** ScreenCaptureKit audio (requires Screen Recording permission, video stream overhead); virtual loopback drivers like BlackHole (third-party, needs installation).

### D2. One private aggregate device for microphone + tap
Create a private aggregate device (`AudioHardwareCreateAggregateDevice`, `kAudioAggregateDeviceIsPrivateKey = true`) containing the input device as a sub-device and the process tap in its tap list, with drift compensation enabled for non-clock sources. A single IOProc (`AudioDeviceCreateIOProcIDWithBlock`) receives microphone and system audio in the same callback with a shared sample clock.
- **Why:** Core Audio handles clock-domain drift between the microphone and output; meets the synchronized-timeline requirement at practically no cost, and makes the mixed and separate-files modes identical up to the final step.
- **Alternatives:** separate AVAudioEngine for the mic plus a separate tap IOProc, aligned by host time. That needs manual drift handling and is used only for the echo-cancellation path (D6).
- **Silent keep-alive output (spike finding):** a global process tap delivers no IO while no process produces output, and an aggregate device containing the tap then stalls: zero IOProc callbacks, so the microphone is not recorded either. This happens whichever sub-device is the clock. Therefore the capture engine starts a silent output (an `AVAudioEngine` source node rendering zeros into the default output) before starting the aggregate IO, and keeps it running for the whole recording. With the keep-alive, recording starts immediately in silence. The microphone stays the main (clock) sub-device. The tap is drift-compensated.
- **Buffer layout (spike finding):** the IOProc input buffer list contains the input streams of the sub-devices in sub-device list order, followed by the tap's stream. The engine computes the microphone and tap buffer indices from the sub-devices' input stream counts at start, and never assumes positions.
- **Measured sync (spike):** with the built-in speakers and a USB microphone, the microphone lags system audio by a constant 7.9–8.2 ms (output latency plus acoustic path) with no measurable drift. No offset correction is applied.

### D3. Device changes rebuild the aggregate device
A `DeviceMonitor` listens to `kAudioHardwarePropertyDevices`, `kAudioHardwarePropertyDefaultInputDevice`, and `kAudioDevicePropertyDeviceIsAlive` on the active input. On a relevant change during a recording, the capture engine tears down and rebuilds the aggregate device with the new input (the new default device, or the default as fallback when the selected device disappears). Writers stay open and keep appending.
- **Why:** an aggregate device's sub-device list is fixed at creation; rebuilding is the documented way to switch.
- **Trade-off:** a short gap (typically < 200 ms) in both tracks during the switch. Both tracks lose the same span, so they stay aligned. Output device changes need no rebuild: the global tap is not bound to an output device. Only the silent keep-alive output (D2) is restarted on the new default output (on `AVAudioEngineConfigurationChange`). Once the IO is running, the tap keeps delivering through long silence (verified for 37 s), so a short keep-alive restart is harmless.

### D4. Real-time thread → ring buffer → writer task
The IOProc copies frames into a preallocated lock-free single-producer/single-consumer ring buffer per source (built on `Synchronization.Atomic`) and computes peak/RMS levels for the meters. A non-real-time writer task drains the buffers roughly every 50 ms and writes to disk. Levels are published to the UI at about 20 Hz through an atomic snapshot that the main actor polls.
- **Why:** keeps the real-time thread free of I/O and locks; Swift 6 friendly because the only shared state is atomics and an `@unchecked Sendable` ring buffer with a single producer and a single consumer.

### D5. Crash-safe intermediate files, convert on stop
While recording, write one 16-bit 48 kHz PCM CAF file per source into the destination folder, named `kRecord <timestamp> (recording mic).caf` and `kRecord <timestamp> (recording system).caf`. The CAF header uses an "unknown data size" so a truncated file stays playable. On stop, a `Finalizer` produces the requested output:
- mixed mode: read both CAFs, mix (system stereo; mic duplicated to L/R; each source at −3 dB, i.e. a gain of 0.707; samples clamped to [−1, 1]), and encode to the target format;
- separate mode: encode each CAF to the target format (mic mono, system stereo);
then delete the intermediate files. Encoding uses `AVAudioFile` with AAC (128 kbps stereo / 64 kbps mono), ALAC 16-bit, or WAV 16-bit settings.
- **Why:** CAF/PCM survives crashes; an `.m4a` written directly lacks its index (moov) until it is closed. Conversion at stop takes seconds for an hour of audio on M1.
- **Trade-off:** temporary disk usage of about 1 GB per hour (3 channels × 16-bit × 48 kHz). The free-space guard (D7) accounts for it.
- **Alternatives:** write AAC directly (not crash-safe); 32-bit float intermediates (2× disk usage for no audible benefit on meeting audio).

### D6. Echo cancellation through AVAudioEngine voice processing
When echo cancellation is enabled, the microphone is captured by `AVAudioEngine.inputNode` with `setVoiceProcessingEnabled(true)` (other-audio ducking minimized through `voiceProcessingOtherAudioDuckingConfiguration`), while system audio comes from a tap-only aggregate device. The two streams are aligned by host time at start; mic frames are dropped or padded to correct accumulated drift against the system audio frame count.
- **Why:** voice processing is the system's echo canceller, and it needs to own the input unit, so it cannot run inside the aggregate device.
- **Trade-off:** a second code path with weaker sync guarantees; voice processing changes the timbre of the voice. Acceptable for an opt-in option.
- **Spike findings:**
  - Echo of speech played through the built-in speakers drops from 23.5 dB to 0.7 dB above the microphone noise floor. Isolated clicks are not suppressed, which is acceptable for meetings.
  - The voice-processing input reports 3 channels with identical content; channel 0 is used.
  - Voice processing adds about 70 ms of latency to the microphone, so host-time alignment is required.
  - Other audio is ducked by about 7.6 dB even with `duckingLevel: .min` and advanced ducking off, and the tap captures the ducked signal. The system track is therefore quieter in this mode. This is documented in the manual QA checklist.
  - While voice processing runs, the output device exposes extra input streams. The tap buffer index is computed after the engine starts (D2 buffer layout).
  - The voice-processing engine drives the output, so it also serves as the keep-alive (D2).

### D7. Storage guard
Before starting, verify the folder exists or can be created and is writable (by creating and deleting a probe file). During recording, check `volumeAvailableCapacityForImportantUsage` every 5 s and stop with a "disk full" error below a 500 MB reserve, which leaves room for finalization. Any write error from the writer, or the folder disappearing, also stops the recording with the matching error; intermediate files written so far are kept.

### D8. App structure (SwiftUI scenes)
- `Window("kRecord", id: "main")`: main window, regular activation policy (Dock icon present), reopened on Dock click.
- `MenuBarExtra` with a custom label: a template SF Symbol when idle; a non-template red-tinted symbol while recording, plus optional `Text(elapsed)`. The menu uses `.menu` style with Start/Stop, `SettingsLink`, and Quit.
- `Settings` scene with a `Form`.
- `NSApplicationDelegateAdaptor` implements `applicationShouldTerminate` → `.terminateLater` while recording, shows an `NSAlert` ("Stop Recording and Quit" / "Cancel"), then replies after finalization.

### D9. State and modules
- `RecordingSession` (`@MainActor @Observable`): state machine `idle → starting → recording → finishing → idle`, plus `error`. Single instance injected into all scenes. Depends on protocols `CaptureEngine`, `RecordingWriter`, `Finalizer`, `StorageGuard`, and `Clock`, so it can be unit-tested with fakes.
- `CaptureEngine` implementations: `AggregateCaptureEngine` (D2) and `VoiceProcessingCaptureEngine` (D6).
- `SettingsStore` (`@Observable`, backed by `UserDefaults`); the destination folder is stored as a security-scoped bookmark.
- `PermissionsManager`: microphone through `AVCaptureDevice.authorizationStatus(for: .audio)` / `requestAccess`; system audio status treated as unknown (no public query API). The first-launch prompt is triggered by briefly creating a tap and starting IO. A finished recording whose system track is entirely digital zero raises the "system audio may be blocked" hint. Verified in the spike: with system audio capture denied, IO runs normally, the microphone is recorded, and the tap delivers exact zeros (peak 0.0), not an error.
- `FileNaming`: pure functions for timestamped names, suffixes, and collision numbering.
- `AudioDeviceCatalog`: lists input devices (UID + name) via the Core Audio HAL.

### D10. Sandbox and folder access
Entitlements: `com.apple.security.app-sandbox`, `com.apple.security.device.audio-input`, `com.apple.security.files.user-selected.read-write`, and `com.apple.security.assets.music.read-write` (for the default `~/Music/kRecord/`). Under the sandbox `NSHomeDirectory()` points into the app container, so the default folder is built from the real home directory (`getpwuid(getuid())`); the spike verified that `~/Music/kRecord/` can be created and written with the `assets.music` entitlement. A custom folder chosen via `NSOpenPanel` is stored as a security-scoped bookmark and resolved at launch; on resolution failure the setting reverts to the default with a notice. Info.plist: `NSMicrophoneUsageDescription`, `NSAudioCaptureUsageDescription`, localized through `InfoPlist.xcstrings`.

### D11. Localization and tests
- All strings go in `Localizable.xcstrings` with `en` (development language) and `ru`.
- Unit tests use Swift Testing (`import Testing`). Hardware-dependent behavior is covered by `docs/manual-qa-checklist.md`.

## Risks / Trade-offs

- [Process taps may behave differently under App Sandbox] → Resolved by the spike: tap + aggregate capture works in the sandboxed app.
- [The aggregate device stalls while no process produces output] → Found in the spike; solved by the silent keep-alive output (D2). The QA checklist covers starting a recording in complete silence.
- [The tap delivers silence instead of an error when permission is denied] → Treat the status as unknown and show the post-recording silence hint (permissions spec).
- [Voice processing ducks other audio or conflicts with the tap] → Confirmed by the spike: no conflict with the tap, but other audio is ducked by about 7.6 dB even at the minimum ducking level, and the system track is recorded ducked. Accepted because the feature is opt-in and off by default.
- [Gap during device switch] → Both tracks lose the same span, so alignment is kept; documented in the manual checklist.
- [Mixing two loud sources can clip] → −3 dB per source plus clamping; acceptable for meeting audio, no other processing by design.
- [Temporary disk usage of about 1 GB/hour] → The storage guard reserve and the error path keep partial audio.
- [`assets.music` entitlement and sandbox container paths] → Verified in the spike with the real `~/Music` path; the `NSOpenPanel` fallback remains for unexpected access failures.

## Migration Plan

Not applicable: first release, no existing users or data.

## Open Questions

- Exact SF Symbol and red tint for the menu bar icon: a cosmetic choice made during implementation.
