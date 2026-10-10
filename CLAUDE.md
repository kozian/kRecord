# kRecord

Native macOS meeting recorder (microphone + system audio). Planning lives in OpenSpec: the current behavior contract is in `openspec/specs/`, and the first change with its design is archived in `openspec/changes/archive/2026-10-10-add-core-recording/`. Read that `design.md` before touching audio code: its decisions record spike and hardware findings that are easy to undo by accident (keep-alive output, voice-processing start order, buffer index computation, 38.7 ms latency constant).

## Build and test

```sh
xcodebuild -project kRecord.xcodeproj -scheme kRecord -derivedDataPath build/DerivedData build
xcodebuild -project kRecord.xcodeproj -scheme kRecord -derivedDataPath build/DerivedData -resultBundlePath build/last.xcresult test
xcrun xcresulttool get test-results summary --path build/last.xcresult   # failure messages; xcodebuild output omits them
rm -rf build/last.xcresult
```

- Claude Code runs over SSH on this Mac. If signing fails with `errSecInternalComponent`, the login keychain is locked in the SSH session: the user must run `security unlock-keychain ~/Library/Keychains/login.keychain-db` before starting `claude`. Ad-hoc fallback: append `CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=` (changes the signature, so macOS asks for audio permissions again).
- Build and test commands need the shell sandbox disabled (keychain and audio access).
- SourceKit diagnostics such as "Cannot find type … in scope" or "No such module 'Testing'" are false positives; trust `xcodebuild`.

## Versions and releases

- The version lives only in `Config/Version.xcconfig`; do not set `MARKETING_VERSION` or `CURRENT_PROJECT_VERSION` in the project file.
- Distributions are made with `scripts/release.sh <MAJOR.MINOR.PATCH>` (`--dry-run` to try), never by hand: it tests, versions, builds, verifies, commits, tags, and packages `build/dist/kRecord-<version>.zip`. Archive finished OpenSpec changes before releasing so the generated `CHANGELOG.md` section includes them. Set `RELEASE_COMMIT_TRAILER` to append a trailer (e.g. the Co-Authored-By line) to the release commit.
- Version bump: new behavior → minor, fixes only → patch (pre-1.0).

## Verifying audio on real hardware

DEBUG builds have a headless recording harness (`kRecord/Debug/DebugRecording.swift`):

```sh
open -n build/DerivedData/Build/Products/Debug/kRecord.app --args -KRDebugRecord 10 \
  [-KRDebugSources all|mic|system] [-KRDebugSaveAsM4A NO] [-KRDebugSeparate YES] [-KRDebugEchoCancellation YES]
```

It records to `~/Music/kRecord/` through `RecordingSession` and the production capture → writer → finalizer pipeline and logs to `~/Music/kRecord/debug-recording.log`. Permission prompts and sound appear on the Mac's own screen and speakers, so ask the user to be at the Mac when a check needs them.

## Code conventions

- Swift 6 language mode, strict concurrency, no default MainActor isolation. Real-time audio code (`AggregateIOContext.process`, `RingBuffer.write`, `LevelSnapshot.publish`) must not allocate, lock, or log.
- Apple frameworks only; no packages.
- Typed throws (`throws(CaptureError)` etc.) across the recording pipeline.
- Tests use Swift Testing; fakes live in `kRecordTests/Fakes/`.
- User-facing strings use `String(localized:)` or SwiftUI `Text("…")` literals. Command-line builds do not add new keys to `Localizable.xcstrings`; add keys (with `ru` translations, `"extractionState": "manual"`) to the catalog by hand, then run `python3 scripts/check-localization.py` after a build: it compares the strings the compiler extracted with the catalog.

## Integration points for the remaining tasks

- `RecordingSession` (`@MainActor @Observable`) is the single source of truth for UI: `start()`, `stop()` (returns after saving, use it for quit), `state`, `formattedElapsedTime`, `levels`, `lastError` / `dismissError()`, `lastResult?.systemAudioSilent`, `canStart`.
- It takes `RecordingSession.Dependencies`: `settings` must return a `RecordingSettings` snapshot (to be produced by `SettingsStore`), and `permittedSources` must return the sources allowed by `PermissionsManager` (system audio status is "unknown" and counts as permitted). Production wiring: `makeEngine: { $0 ? VoiceProcessingCaptureEngine() as any CaptureEngine : AggregateCaptureEngine() }`, `makeWriter: { AACRecordingWriter() }`, `finalizer: AudioFinalizer()`, `storage: FileSystemStorageGuard()`.
- `HomeDirectory.defaultRecordingsFolder` is the real `~/Music/kRecord/` (the sandbox's `NSHomeDirectory()` is the container).
- Input device listing should reuse `CoreAudioHAL` (`allDevices`, `inputStreams(of:)`, `uid(of:)`, `name(of:)`) and `DeviceMonitor` for change notifications.
