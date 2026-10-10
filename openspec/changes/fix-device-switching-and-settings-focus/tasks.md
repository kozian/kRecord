# Tasks

## 1. Echo-cancellation device switching

- [ ] 1.1 Add a method to `AggregateCaptureEngine` that rebuilds the running aggregate (tear down IOProc and aggregate, build again with the same tap, ring buffers, level snapshot, and timeline anchor; same candidate fallback and sample-rate rule as device changes); verify the existing tests pass and a debug recording in system-only mode with a forced rebuild keeps click spacing at 1.0 s
- [ ] 1.2 Make `VoiceMicrophonePath.prepare(inputFormat:)` reset and rebuild the converter for each new input format, and add padding of the microphone ring up to the system timeline's frame count; verify with unit tests (converter rebuilt for 44.1 kHz after 48 kHz; padding writes exactly the missing frames, and nothing when the microphone is ahead)
- [ ] 1.3 Restructure `VoiceProcessingCaptureEngine`: `DeviceMonitor` plus the engine's configuration-change notification trigger a rebuild when the wanted microphone changes, dies, or the engine stopped; the rebuild creates a fresh voice-processing engine (resolved device, then default input, then none with a silent aligned microphone), then rebuilds the system aggregate; emits `.inputDeviceChanged`; pads the microphone at stop; verify the project builds with no warnings and all tests pass
- [ ] 1.4 Verify on hardware with the debug harness and echo cancellation on: switch the default input during a recording (System Default) and check that the microphone continues from the new device, the system track keeps 1.0 s click spacing, both separate files have the same length, and strong clicks stay within about 10 ms of each other before and after the switch; record the numbers in the design
- [ ] 1.5 Add QA checklist items for echo cancellation: selected microphone unplugged (fallback to default or silence, system audio continues) and plugged back in (selected microphone used again, aligned); verify the items are in `docs/manual-qa-checklist.md` and mapped in `docs/spec-coverage.md`

## 2. Settings from the menu bar

- [ ] 2.1 Replace the `SettingsLink` in `MenuBarContent` with a button that activates the app and calls the `openSettings` environment action; verify the build, that the menu still shows exactly the three actions, and that the strings check (`scripts/check-localization.py`) passes
- [ ] 2.2 Add the "Settings… while another app is active" check to the menu bar section of the QA checklist and to `docs/spec-coverage.md`; verify by hand: with Finder active, choose "Settings…" from the menu bar menu and the Settings window comes to the front

## Workflow follow-up

- Archive the change with `/opsx:archive` after the hardware checks pass.
