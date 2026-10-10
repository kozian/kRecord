# Spec coverage

Every scenario of the `add-core-recording` specs and where it is checked: an automated test (Swift Testing, in `kRecordTests/`), a harness run on real hardware (the DEBUG recording and remote-control harnesses described in `CLAUDE.md`), or an item of [manual-qa-checklist.md](manual-qa-checklist.md) (section in brackets). Scenarios that need a person or hardware (sound, permission prompts, menus, drives) are in the checklist.

## audio-capture

| Scenario | Checked by |
|---|---|
| Both sources recorded | QA [Audio capture]; harness (clicks + microphone) |
| Audio from multiple apps | QA [Audio capture] |
| Multichannel audio interface | `RingBufferTests.takesFirstChannelsFromWiderSource`; QA [Audio capture] |
| Stereo content | `RecordingWriterTests.mixedKeepsSystemStereoImage`, `separateFilesKeepSourcesApart`; QA [Audio capture] |
| Long recording stays in sync | harness (60 s, 7.9 ms offset without drift); QA [Audio capture] 60-minute sync |
| Default input changes mid-recording | harness (default input switched mid-recording); QA [Audio capture] |
| Specific microphone selected | `SettingsStoreTests.settingsPersistAcrossInstances`, `RecordingSessionTests.settingsAreSnapshotAtStart`; QA [Audio capture] |
| Aggregate devices are not offered | `AudioDeviceCatalogTests.systemEnumerationIsConsistent` (kRecord's aggregate hidden); QA [Settings] No aggregate devices |
| Device list reflects hardware changes | `AudioDeviceCatalogTests`; QA [Settings] hot-plug |
| Selected microphone unplugged during recording | harness (USB microphone unplugged and replugged); QA [Audio capture] |
| Selected microphone unavailable at start | QA [Audio capture]; `AudioDeviceCatalogTests` (list without the device) |
| Headphones connected mid-recording | QA [Audio capture] output device changes |
| Echo cancellation enabled with speakers | harness (echo 23.5 dB → 4.8 dB above the noise floor); QA [Audio capture] |
| Echo cancellation disabled by default | `SettingsStoreTests.firstLaunchDefaults` |
| Levels reflect activity | `AudioLevelsTests`, `FakeCaptureEngineTests`; QA [Audio capture] level meters |
| Microphone permission denied | `PermissionsManagerTests.permittedSourcesFollowStatuses`, `AppModelTests.startRecordsOnlySystemAudioWhenMicrophoneIsDenied`; QA [Permissions] |
| Microphone turned off | `RecordingSessionTests.microphoneOffRecordsSystemOnly`, `AppModelTests.microphoneOffIsNotRequestedOrRecorded`; QA [Recording session] Microphone off |
| Microphone off (not opened) | `AppModelTests.microphoneOffIsNotRequestedOrRecorded` (no microphone in the capture configuration); QA [Recording session] Microphone off |
| System audio off | `RecordingSessionTests.systemAudioOffRecordsMicrophoneOnly`; QA [Recording session] System audio off |
| Both sources off | `RecordingSessionTests.bothSourcesOffCannotStart`, `AppModelTests.bothSourcesOffDisableTheControl`; QA [Recording session] Both off |

## recording-output

| Scenario | Checked by |
|---|---|
| Default output | `FinalizerTests.saveAsM4AReplacesStreams`; harness; QA [Recording output] |
| Microphone centered | `RecordingWriterTests.mixedMicrophoneIsCenteredAtMinusThreeDecibels`, `mixValuesAreClamped` |
| Separate files produced | `RecordingWriterTests.separateFilesKeepSourcesApart`; harness |
| Separate files are aligned | harness (separate tracks 7.9 ms apart); QA [Recording output] Separate files |
| Only one source recorded | `RecordingSessionTests.separateFilesWithMicrophoneOffWriteOneStream`; harness (microphone off → only the `(system)` file); QA [Recording session] Microphone off |
| Default format | `FinalizerTests.repackagesWithoutReencoding`, `saveAsM4AReplacesStreams`; `AACEncodingTests` |
| Save as m4a off | `FinalizerTests.withoutM4AStreamsAreFinal`; harness; QA [Recording output] |
| Saving as m4a does not re-encode | `FinalizerTests.repackagesWithoutReencoding` (identical packets, exact duration) |
| No save dialog | QA [Recording output] Default output |
| Mixed file name | `FileNamingTests.mixedFileNames`, `baseNameUsesLocalStartTime` |
| Separate file names | `FileNamingTests.separateFileNames` |
| Raw AAC file name | `FileNamingTests.mixedFileNames`; `RecordingSessionTests.separateFilesNameEachCapturedSource` |
| Name collision | `FileNamingTests.collisionAppendsNumber`, `eitherExtensionTakesTheName`, `separateFilesShareOneNumber`; QA [Recording output] |
| App killed during recording | `RecordingWriterTests.unclosedStreamIsPlayable`; harness (`kill -9`); QA [Recording output] Crash safety |
| Normal stop leaves only final files | `FinalizerTests.saveAsM4AReplacesStreams`, `failureKeepsStreams` |
| Disk full | `StorageGuardTests`, `RecordingSessionTests.storageProblemDuringRecordingStopsWithError`; QA [Recording output] |
| Destination folder removed | `StorageGuardTests.checkReportsRemovedFolder`, `RecordingSessionTests.storageProblemDuringRecordingStopsWithError`; QA [Recording output] |
| Unwritable folder | `StorageGuardTests.unwritableFolderIsRejected`, `RecordingSessionTests.unwritableFolderBlocksStart`; QA [Recording output] |
| First recording | `StorageGuardTests.createsMissingFolder`; QA [Recording output] Folder created on demand |

## recording-session

| Scenario | Checked by |
|---|---|
| Start then stop | `RecordingSessionTests.startThenStopSavesRecording` |
| Started from menu bar / Stopped from main window | one shared `RecordingSession` (`AppModel`); QA [Recording session] Shared state |
| Timer progresses | `RecordingSessionTests.elapsedTimeFollowsClock`, `elapsedFormat` |
| Finalizing a long recording | `RecordingSessionTests.startBlockedWhileFinishing`, `AppModelTests.controlFollowsSessionState`; QA [Recording session] |
| Error during recording | `RecordingSessionTests` (storage, capture, and writer failure tests); QA [Main window] Error display |
| Quit confirmed / cancelled / while idle | `AppModelTests` (`confirmedQuitStopsAndSavesTheRecording`, `cancelledQuitKeepsRecording`, `quitWhileIdleNeedsNoConfirmation`, `quitWaitsForSavingWithoutAsking`); harness (real alert answered both ways); QA [Recording session] |

## main-window

| Scenario | Checked by |
|---|---|
| Reopen after closing | harness (Dock click reopens the window); QA [Main window] |
| Window closed during recording | harness (recording and menu bar item survive); QA [Main window] |
| Toggle recording | `AppModelTests.controlFollowsSessionState`; QA [Main window] Record button |
| Button unavailable while saving | `AppModelTests.controlFollowsSessionState`; `ViewSnapshotTests.mainWindowSaving` |
| Idle display | `RecordingSessionTests.elapsedTimeFollowsClock`; QA [Main window] |
| Meters during recording | `ViewSnapshotTests.mainWindowRecording`; QA [Main window] Level meters |
| Picker synced with settings | one `SettingsStore` behind both pickers (`MicrophonePicker`); QA [Main window] |
| Picker locked during recording | `AppModelTests.controlFollowsSessionState`; `ViewSnapshotTests.settingsLockedWhileRecording`; QA [Main window] |
| Microphone permission missing | `ViewSnapshotTests.mainWindowMicrophoneDenied`; QA [Main window] |
| Both permissions missing | `AppModelTests.cannotStartWhenNothingIsPermitted`; `ViewSnapshotTests.mainWindowNothingPermitted` (cannot be provoked by hand: the system audio status is unknown) |
| Error shown | `ViewSnapshotTests.mainWindowError`; QA [Main window] Error display |
| Open recordings folder | `AppModelTests.revealCreatesAndOpensTheDestinationFolder`; QA [Main window] Recordings folder button |
| Open settings from the main window | QA [Main window] Settings button |
| Available during a recording | `ViewSnapshotTests.mainWindowRecording` (icon buttons enabled); QA [Main window] Buttons during a recording |
| No source turned on | `AppModelTests.bothSourcesOffDisableTheControl`, `ViewSnapshotTests.mainWindowSourceSwitches`; QA [Recording session] Both off |
| Turning the microphone off | `ViewSnapshotTests.mainWindowSourceSwitches` (empty microphone meter while recording); QA [Recording session] Microphone off |
| Checkboxes on by default / state remembered | `SettingsStoreTests.firstLaunchDefaults`, `sourceSwitchesPersistAndReachTheSnapshot`; QA [Recording session] Switches remembered and locked |
| Checkboxes locked during recording | `ViewSnapshotTests.mainWindowSourceSwitches` (disabled checkboxes while recording); QA [Recording session] Switches remembered and locked |

## menu-bar

| Scenario | Checked by |
|---|---|
| Item visible after closing window | harness (status item window present with the main window closed); QA [Menu bar] |
| Icon turns red / returns to grey | `ViewSnapshotTests.menuBarIconColors`, `menuBarRecordingWithTime`; QA [Menu bar] |
| Time shown / Time hidden by default | `SettingsStoreTests.firstLaunchDefaults`; `ViewSnapshotTests.menuBarRecordingWithTime`; QA [Menu bar] |
| Menu while idle / while recording | QA [Menu bar] Menu contents |
| Start unavailable while saving | `AppModelTests.controlFollowsSessionState`; QA [Recording session] |
| Open settings | harness (Settings window opens with the main window closed); QA [Menu bar] Settings from the menu |
| Quit while idle | `AppModelTests.quitWhileIdleNeedsNoConfirmation`; harness; QA [Menu bar] |

## permissions

| Scenario | Checked by |
|---|---|
| First launch prompts | `AppModelTests.firstLaunchRequestsPermissionsOnce`; QA [Permissions] |
| Microphone prompt text | `Info.plist` / `InfoPlist.xcstrings` (checked in the built bundle); QA [Permissions] |
| Permission granted later | `PermissionsManagerTests.refreshPicksUpChangesFromSystemSettings`; QA [Permissions] Granting later |
| Status not determinable | `PermissionsManagerTests.unknownSystemAudioKeepsRecordingEnabled` |
| Silent system audio hint | `RecordingWriterTests.silentSystemTrackIsReported`, `RecordingSessionTests.silentSystemAudioIsReported`, `ViewSnapshotTests.mainWindowSilentSystemAudioHint`; QA [Main window] |
| Only system audio permitted | `PermissionsManagerTests.permittedSourcesFollowStatuses`; QA [Permissions] |
| No permissions | `PermissionsManagerTests.permittedSourcesFollowStatuses`, `RecordingSessionTests.startBlockedWithoutPermissions` |
| Open microphone privacy pane | `PermissionsManagerTests.opensThePrivacyPanes`; QA [Permissions] Deep links |
| No network use | the app has no network entitlement (App Sandbox without `com.apple.security.network.client`); QA [Permissions] |

## settings

| Scenario | Checked by |
|---|---|
| Settings window contents | `ViewSnapshotTests.settingsDefault`; QA [Settings] |
| First launch defaults | `SettingsStoreTests.firstLaunchDefaults`, `realDefaultFolderIsMusicKRecord`; QA [Settings] |
| Restart keeps settings | `SettingsStoreTests.settingsPersistAcrossInstances`; QA [Settings] Persistence |
| Custom folder remains writable after restart | `SettingsStoreTests.customFolderSurvivesRestart`, `FolderRestorationTests` (fake access); QA [Settings] Persistence (the real sandbox bookmark is only exercised here) |
| Change folder | `SettingsStoreTests.choosingAnotherFolderReleasesThePreviousOne`; QA [Settings] Persistence |
| Reveal folder | QA [Settings] Show in Finder |
| Custom folder deleted | `SettingsStoreTests.deletedCustomFolderRevertsToDefaultWithNotice`, `FolderRestorationTests`; QA [Settings] |
| Save as m4a locked during recording | `ViewSnapshotTests.settingsLockedWhileRecording`; QA [Settings] |
| Menu bar time toggled during recording | `ViewSnapshotTests.settingsLockedWhileRecording` (switch stays enabled); QA [Menu bar] |
| Russian system language | harness (menus in Russian with `-AppleLanguages (ru)`); `ViewSnapshotTests` renders in Russian; `scripts/check-localization.py`; QA [Localization] |
| Unsupported system language | harness (menus in English with `-AppleLanguages (de)`); QA [Localization] |
