# Design

## Context

See proposal.md. Current state (archived design `openspec/changes/archive/2026-10-10-add-core-recording/design.md`):

- System audio comes from one global stereo process tap (`CATapDescription(stereoGlobalTapButExcludeProcesses: [])`) inside a private aggregate with the microphone as clock (D1, D2). A global tap stalls the aggregate while no process plays audio, so kRecord plays digital silence (keep-alive) for the whole recording.
- `RecordingSession` captures `permittedSources`; `CaptureConfiguration` carries the input device UID and the sources.
- Device changes rebuild the aggregate with the same tap, ring buffers, and timeline (D3); echo cancellation records the microphone through voice processing and system audio through a tap-only aggregate (D6).

Constraints: macOS 15+ (user decision: no macOS 26-only API such as `CATapDescription.bundleIDs` or `processRestoreEnabled`), Apple frameworks only, App Sandbox.

## Goals / Non-Goals

**Goals:**
- Record one application's audio, including its helper processes, with the same alignment and crash safety as "All Audio".
- Keep recording through the application quitting and starting again.
- Turn sources off so that an off microphone is never opened.

**Non-Goals:**
- Several applications at once, or "All Audio except …".
- Changing the source or the checkboxes during a recording.

## Decisions

### D1. Which applications are offered
The picker lists "All Audio" first, then the running regular applications (`NSWorkspace.runningApplications` with activation policy `.regular`, excluding kRecord), sorted by name. All running apps are listed, not only those currently playing, because a meeting app may open audio only when a call starts. The selection is stored as bundle ID plus display name, so a selected app that is not running can be shown as "<name> (not running)". A new `AudioApplicationCatalog` (next to `AudioDeviceCatalog`) keeps the list current from `NSWorkspace` launch/terminate notifications.
- **Alternative:** list only Core Audio process objects that are playing — misses apps that have not opened audio yet.

### D2. Which processes belong to an application
A Core Audio process object (`kAudioHardwarePropertyProcessObjectList`) belongs to the selected application when its bundle ID (`kAudioProcessPropertyBundleID`) equals the application's bundle ID or starts with it followed by a dot (helpers such as `com.google.Chrome.helper`), or when its PID (`kAudioProcessPropertyPID`) descends from the application's PID (parent chain via `proc_pidinfo`). Task 1.1 measures this on Safari, Chrome, Firefox, Zoom, Teams, Telegram, and Music before the rule is final.
- **Known limitation to confirm in 1.1:** Safari plays web audio from the shared `com.apple.WebKit.GPU` process, which is not a descendant of Safari and serves other WebKit apps too. If no public signal separates it, selecting Safari includes that process, and the docs say audio from other WebKit-based apps may also be recorded.

### D3. The per-application tap keeps running in silence
For a selected application the tap is a private stereo mixdown of the application's processes **plus kRecord's own process** (`CATapDescription(stereoMixdownOfProcesses:)`). kRecord's keep-alive output is digital silence, so it adds nothing to the recording, but it keeps the tap delivering IO while the application is silent or not running — the stall found for the global tap would otherwise stop the microphone too. "All Audio" keeps the global tap.
- **Verification (1.2):** a recording with a silent or not-running selected application keeps both tracks at full length.

### D4. Following the application's processes during a recording
`AggregateCaptureEngine` watches `kAudioHardwarePropertyProcessObjectList` (and `NSWorkspace` launch/terminate notifications) while a per-application tap is in use. When the set of the application's process objects changes, it updates the tap's process list by setting `kAudioTapPropertyDescription` on the existing tap; if that is not supported, it rebuilds tap and aggregate with the D3 rebuild path (same rings and timeline, short gap on both tracks). Task 1.3 decides between the two.
- **Why:** a restarted app gets new process objects; a tap made from the old ones stays silent.

### D5. Turning sources off
`SettingsStore` stores two booleans, microphone source on and system audio source on (default both on), plus the system audio source selection. `RecordingSettings` carries them, and `RecordingSession` captures `permittedSources ∩ enabledSources`; `canStart` is false when that set is empty. Because a source that is off never reaches `CaptureConfiguration`, the existing single-source paths apply unchanged: no microphone device or voice-processing engine is opened, and in separate-files mode the writer creates only the recorded source's file.
- **Alternative:** capture and mute — rejected by the user decision (microphone must not be opened).

### D6. Capture configuration
`CaptureConfiguration` gains the system audio source (`.all` or `.application(bundleID)`). `AggregateCaptureEngine` builds the global or per-application tap from it; `VoiceProcessingCaptureEngine` passes it to its system-only aggregate. The silent-system-audio hint keeps working; with an application selected its text names the application ("The last recording has no audio from <name>.") and still links to the privacy settings.

### D7. UI
Each level meter in the main window gets a leading checkbox; the system audio source picker sits next to the system audio meter, mirroring the microphone picker below the microphone meter, and appears in the Settings window under Recording. Both pickers and both checkboxes are disabled unless the session is idle. "All Audio" is the first picker item and the default. New strings get Russian translations ("Весь звук", "(не запущено)").

### D8. Coordination with `fix-device-switching-and-settings-focus`
Both changes modify the settings requirement "Available settings". Archive the fix change first; before archiving this change, refresh this delta so its "Available settings" block also carries the fix change's "Settings shown without scrolling" scenario.

## Risks / Trade-offs

- [Helper-process grouping misses an app's audio process or includes another app's (shared WebKit GPU process)] → Measured in task 1.1 for common meeting apps and browsers; limitations documented in the QA checklist and README.
- [Updating a live tap's process list is not supported] → Fall back to rebuilding tap and aggregate (gap under half a second on both tracks, alignment kept).
- [A process appears only when the app starts playing, so the first moments of its audio can be lost before the tap is updated] → The process-list listener reacts within a fraction of a second; acceptable for meetings.
- [Many process-list notifications during app launch] → Coalesced like device changes; the tap is updated only when the matching set changes.
