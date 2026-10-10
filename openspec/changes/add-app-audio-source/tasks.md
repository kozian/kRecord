# Tasks

## 1. Spike: per-application capture on macOS 15+

- [ ] 1.1 Measure which Core Audio process objects (bundle ID, PID, parent chain) play the audio of Safari, Chrome, Firefox, Zoom, Teams, Telegram, and Music, and settle the D2 grouping rule; verify by recording each app with the rule and record the findings (including the Safari/WebKit outcome) in the design
- [ ] 1.2 Verify D3: a per-application tap that also contains kRecord's process keeps the aggregate running while the app is silent or not running; verify with a debug recording of 30 s where the app plays only in the middle: both tracks are full length and the microphone is continuous
- [ ] 1.3 Decide D4: check whether setting `kAudioTapPropertyDescription` on a running tap updates its process list; verify with an app restart during a debug recording and record the decision (live update or rebuild) in the design

## 2. Application catalog and setting

- [ ] 2.1 Implement `AudioApplicationCatalog`: running regular apps (bundle ID, name), kept current from `NSWorkspace` notifications, and the process objects belonging to an app per the D2 rule; verify with unit tests on the grouping rule using fake process data, and a test that the real list contains Finder
- [ ] 2.2 Add the system audio source selection (bundle ID and name, default "All Audio") to `SettingsStore`, `RecordingSettings`, and `CaptureConfiguration`; verify with unit tests for the default, persistence, and the snapshot

## 3. Capture

- [ ] 3.1 Build the global or per-application tap (D3, D5) in `AggregateCaptureEngine` and the echo-cancellation path from the configured source; verify existing tests pass and a debug recording with one app selected contains that app and not a second playing app
- [ ] 3.2 Follow the application's processes during a recording (D4): pick up an app started after the recording began and an app restarted mid-recording, with silence while it is gone; verify with debug recordings (app not running at start, app restarted) that the system track is full length, the app is audible after it starts, and clicks stay aligned with the microphone

## 4. Interface

- [ ] 4.1 Main window: system audio source picker ("All Audio" first, "<name> (not running)" for a missing selection) next to the system audio meter, disabled unless idle; verify with view snapshots (default, app selected, app not running, recording) in English and Russian
- [ ] 4.2 Settings window: the same picker under Recording, locked during a recording; silent-audio hint naming the selected app (D5); verify with snapshots and `scripts/check-localization.py`
- [ ] 4.3 DEBUG recording harness: `-KRDebugApp <bundleID>` flag; verify the harness records one app with it

## 5. Documentation and integration

- [ ] 5.1 Add QA checklist items (app selection, browser tab audio, app not running / restarted, other apps not recorded) and map every new scenario in `docs/spec-coverage.md`; verify each new spec scenario has a test or checklist entry
- [ ] 5.2 Run an end-to-end check on hardware: a 5-minute recording of one app (separate files) while another app also plays, with the app restarted once; verify only the selected app is in the system track, the track is complete, and the tracks stay aligned

## Workflow follow-up

- Archive `fix-device-switching-and-settings-focus` before this change, and refresh this change's settings delta as described in design D7 before archiving it.
