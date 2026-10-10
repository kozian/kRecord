# Tasks

## 1. Spike: per-application capture on macOS 15+

- [ ] 1.1 Measure which Core Audio process objects (bundle ID, PID, parent chain) play the audio of Safari, Chrome, Firefox, Zoom, Teams, Telegram, and Music, and settle the D2 grouping rule; verify by recording each app with the rule and record the findings (including the Safari/WebKit outcome) in the design
- [ ] 1.2 Verify D3: a per-application tap that also contains kRecord's process keeps the aggregate running while the app is silent or not running; verify with a debug recording of 30 s where the app plays only in the middle: both tracks are full length and the microphone is continuous
- [ ] 1.3 Decide D4: check whether setting `kAudioTapPropertyDescription` on a running tap updates its process list; verify with an app restart during a debug recording and record the decision (live update or rebuild) in the design

## 2. Application catalog

- [ ] 2.1 Implement `AudioApplicationCatalog`: running regular apps (bundle ID, name), kept current from `NSWorkspace` notifications, and the process objects belonging to an app per the D2 rule; verify with unit tests on the grouping rule using fake process data, and a test that the real list contains Finder

## 3. Capture

- [ ] 3.1 Add the system audio source to `CaptureConfiguration` and build the global or per-application tap (D3, D6) in `AggregateCaptureEngine` and the echo-cancellation path; verify existing tests pass and a debug recording with one app selected contains that app and not a second playing app
- [ ] 3.2 Follow the application's processes during a recording (D4): pick up an app started after the recording began and an app restarted mid-recording, with silence while it is gone; verify with debug recordings (app not running at start, app restarted) that the system track is full length, the app is audible after it starts, and clicks stay aligned with the microphone

## 4. Settings and session

- [ ] 4.1 Add the system audio source selection and the two source switches (default on) to `SettingsStore` and `RecordingSettings`; verify with unit tests for defaults, persistence, and the snapshot
- [ ] 4.2 Make `RecordingSession` capture `permittedSources ∩ enabledSources` and refuse to start when that set is empty; verify with unit tests (microphone off → system only and no microphone in the configuration; both off → cannot start; separate files with the microphone off → one stream)

## 5. Interface

- [ ] 5.1 Main window: checkbox per level meter, system audio source picker ("All Audio" first, "<name> (not running)" for a missing selection) next to the system audio meter, all disabled unless idle, record button disabled when nothing is on; verify with view snapshots (idle, recording, app not running, both off) in English and Russian
- [ ] 5.2 Settings window: system audio source picker under Recording, locked during a recording; adjust the silent-audio hint text when an app is selected (D6); verify with snapshots and `scripts/check-localization.py`
- [ ] 5.3 DEBUG recording harness: flags for the system audio source (`-KRDebugApp <bundleID>`) and source switches; verify the harness records with each flag

## 6. Documentation and integration

- [ ] 6.1 Add QA checklist items (app selection, helper-process audio in a browser, app not running / restarted, microphone off with no in-use indicator, both off, separate files with one source) and map every new scenario in `docs/spec-coverage.md`; verify each new spec scenario has a test or checklist entry
- [ ] 6.2 Run an end-to-end check on hardware: a 5-minute recording of one app (separate files) while another app also plays, with the app restarted once; verify only the selected app is in the system track, the track is complete, and the tracks stay aligned

## Workflow follow-up

- Archive `fix-device-switching-and-settings-focus` before this change, and refresh this change's settings delta as described in design D8 before archiving it.
