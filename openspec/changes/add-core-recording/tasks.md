# Tasks

## 1. Project setup

- [x] 1.1 Create Xcode project `kRecord` (SwiftUI app, macOS 15 deployment target, Swift 6 language mode, strict concurrency complete) with a unit test target using Swift Testing; verify `xcodebuild build` and `xcodebuild test` succeed on the empty project
- [x] 1.2 Configure entitlements (app sandbox, audio input, user-selected read-write, assets.music read-write) and Info.plist usage descriptions (`NSMicrophoneUsageDescription`, `NSAudioCaptureUsageDescription`); verify with `codesign -d --entitlements - <app>` after build
- [x] 1.3 Add `Localizable.xcstrings` and `InfoPlist.xcstrings` with `en` as the development language and `ru` added; verify both languages appear in the built app bundle
- [x] 1.4 Add `.gitignore` for Xcode/Swift and a short `README.md` (purpose, requirements: macOS 15+ / Apple silicon, build instructions); verify the README build command works as written
- [x] 1.5 Create `docs/manual-qa-checklist.md`: a Markdown checklist (`- [ ]` items) of manual checks, with sections per capability (audio capture, output, session, main window, menu bar, settings, permissions, localization) and a header explaining how to run it (test environment, required hardware: second microphone, headphones, external drive); verify the file exists with all sections. Later groups append their items to it

## 2. Capture spike (de-risk D1/D2/D6/D10)

- [x] 2.1 Build a throwaway capture path in the sandboxed app: global process tap + private aggregate device with the default input, recording 10 s to two CAF files; verify by playback that both files contain audio and stay aligned (clap test)
- [x] 2.2 Verify in the spike: (a) behavior when the system audio permission is denied (silence vs. error), (b) the voice-processing input can run alongside a tap-only aggregate device and how much ducking remains, (c) the default `~/Music/kRecord` path is writable under the sandbox; record findings and any deviations in `design.md` (update Risks/Decisions) before continuing

## 3. Core utilities

- [x] 3.1 Implement `FileNaming` (timestamp format `kRecord YYYY-MM-DD HH-mm-ss`, ` (mic)` / ` (system)` / ` (recording …)` suffixes, extension per format, collision numbering ` 2`, ` 3`…); verify with unit tests covering all spec scenarios
- [x] 3.2 Implement `OutputFormat` (AAC/ALAC/WAV → extension and `AVAudioFile` settings at 48 kHz, AAC ≥128 kbps stereo); verify with unit tests on generated settings
- [x] 3.3 Implement the lock-free SPSC ring buffer on `Synchronization.Atomic`; verify with unit tests for wraparound, overflow handling, and a concurrent producer/consumer stress test
- [x] 3.4 Implement level calculation (peak/RMS → normalized meter value) with an atomic snapshot; verify with unit tests on known signals (silence, full-scale sine)

## 4. Settings

- [ ] 4.1 Implement `SettingsStore` (@Observable, UserDefaults) with all six settings and spec defaults; verify with unit tests for defaults and persistence round-trip using an isolated UserDefaults suite
- [ ] 4.2 Implement destination folder handling: default real `~/Music/kRecord/` path, security-scoped bookmark save/resolve, revert to default with a notice flag on failure; verify with unit tests (stale or missing bookmark → default + notice)
- [ ] 4.3 Implement `AudioDeviceCatalog` (input devices UID + name, change notifications); verify with a unit test that the list is non-empty on a Mac with a built-in microphone, and add manual checks for hot-plugging to the QA checklist
- [ ] 4.4 Build the Settings window (`Settings` scene, `Form`: folder path + Choose… + Reveal in Finder, microphone picker, format picker, separate-files toggle, echo-cancellation toggle, menu-bar-time toggle; recording-related controls disabled while recording); verify manually and add settings items to the QA checklist

## 5. Permissions

- [ ] 5.1 Implement `PermissionsManager`: microphone status/request via AVCaptureDevice, system audio prompt trigger (short tap + IO start), system audio status = unknown, refresh on app activation; verify with unit tests on the state mapping using a fake authorization provider
- [ ] 5.2 Request both permissions on first launch (flag in settings) and implement "Open System Settings" deep links for the Microphone and Audio Capture privacy panes; verify manually on a fresh `tccutil reset` and add permission items to the QA checklist

## 6. Capture engine

- [x] 6.1 Define the `CaptureEngine` protocol (start with input device + sources, stop, ring buffers, levels, error/route events) and a `FakeCaptureEngine` for tests; verify the project builds and the fake produces deterministic frames in a unit test
- [x] 6.2 Implement `AggregateCaptureEngine` (global stereo tap, private aggregate with the mic as clock and a drift-compensated tap, silent keep-alive output restarted on output changes, buffer indices computed from sub-device stream counts, single IOProc copying mono mic and stereo system frames into ring buffers and updating levels; supports mic-only and system-only modes) and remove the spike code; verify with a 60 s manual recording clap test including a start in complete silence, and add capture items to the QA checklist
- [ ] 6.3 Implement `DeviceMonitor` and aggregate rebuild on default-input change and on loss of the selected device (fallback to default, selection remembered); verify manually by switching the default input and unplugging a USB mic mid-recording, and add these cases to the QA checklist
- [ ] 6.4 Implement `VoiceProcessingCaptureEngine` (AVAudioEngine input with voice processing and minimized ducking + tap-only aggregate, host-time alignment and drift correction); verify manually with speakers that system audio is suppressed in the mic track, and add the echo-cancellation check to the QA checklist

## 7. Recording output

- [x] 7.1 Implement `RecordingWriter`: writer task draining the ring buffers into 16-bit 48 kHz CAF intermediates in the destination folder; verify with a unit test feeding fake frames and reading the CAFs back (frame counts, channel counts)
- [x] 7.2 Implement `Finalizer`: mixed mode (mic centered, −3 dB per source, clamp) and separate mode, encoding to AAC/ALAC/WAV, collision-safe final names, deletion of intermediates, detection of an all-zero system track; verify with unit tests on generated signals (mix values, centered mic, output format/extension, no leftover temp files)
- [x] 7.3 Implement `StorageGuard` (pre-start writable probe and folder creation, 5 s free-space check with 500 MB reserve, write-error and folder-loss detection); verify with unit tests using an injected capacity provider and an unwritable temp directory, and add disk-full and drive-eject cases to the QA checklist
- [ ] 7.4 Verify crash safety manually: force-quit during a recording and confirm the intermediate CAF plays in QuickTime; add this check to the QA checklist

## 8. Recording session

- [ ] 8.1 Implement `RecordingSession` state machine (idle/starting/recording/finishing/error), elapsed time `HH:MM:SS` from an injected clock, settings snapshot at start, choice of engine by the echo-cancellation setting, error mapping to localized messages; verify with unit tests on all transitions using fakes (start/stop, error during recording → idle + error, start blocked while finishing, start blocked with no permissions)
- [ ] 8.2 Implement quit handling via `NSApplicationDelegateAdaptor` (`applicationShouldTerminate` → confirmation alert "Stop Recording and Quit" / "Cancel" → finalize → quit; quit immediately when idle); verify manually and add quit cases to the QA checklist

## 9. Main window

- [ ] 9.1 Build the main window (`Window` scene): record/stop button with saving state, elapsed time, two labeled level meters, microphone picker bound to settings and locked while recording; verify manually and add main-window items to the QA checklist
- [ ] 9.2 Add permission warnings (missing microphone, post-recording system-silence hint, record disabled when nothing is permitted) and error display with dismiss; verify manually with permissions revoked via `tccutil reset`
- [ ] 9.3 Ensure closing the window keeps recording and the Dock icon reopens the window; verify manually and add the check to the QA checklist

## 10. Menu bar

- [ ] 10.1 Build `MenuBarExtra`: grey template icon when idle, red icon while recording, optional elapsed time from settings (applies immediately); verify manually in light and dark menu bar and add the items to the QA checklist
- [ ] 10.2 Add menu items Start/Stop Recording (disabled while finishing), Settings… (opens and focuses the Settings window), Quit (through the quit confirmation); verify manually that state stays in sync with the main window

## 11. Localization and integration

- [ ] 11.1 Translate all strings in `Localizable.xcstrings` and `InfoPlist.xcstrings` to Russian; verify that no strings are untranslated in the catalog and check the UI with `-AppleLanguages (ru)` and `(de)` (English fallback); add localization items to the QA checklist
- [ ] 11.2 Review `docs/manual-qa-checklist.md` against every spec scenario that unit tests do not cover and fill gaps; verify each spec in `specs/` maps to at least one automated test or checklist item
- [ ] 11.3 Run the full manual QA checklist on an M1-class Mac with a 60-minute meeting recording (mixed AAC) plus short recordings in ALAC, WAV and separate-files mode; verify all items pass and record results and the macOS version at the end of the checklist

## Workflow follow-up

- Archive the change with `/opsx:archive` after the checklist passes and the result is reviewed.
