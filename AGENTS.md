# kRecord

Native macOS meeting recorder (microphone + system audio). Planning lives in OpenSpec: the current behavior contract is in `openspec/specs/`, finished changes with their designs are in `openspec/changes/archive/` (one per feature or fix, newest last), and `CHANGELOG.md` lists what each release contains. Read the `design.md` of `2026-10-10-add-core-recording` before touching audio code: its decisions record spike and hardware findings that are easy to undo by accident (keep-alive output, voice-processing start order, buffer index computation, 38.7 ms latency constant). `2026-10-10-fix-device-switching-and-settings-focus` adds the echo-cancellation device switching findings (no system aggregate rebuild per switch, stall watchdog).

Developer documentation for people is in `DEVELOPMENT.md`; `README.md` is for users. Machine-specific notes (the developer's own Mac and hardware) belong in the untracked `CLAUDE.md`, not here.

## Rules for agents

- Code, comments, commit messages, and repository documents are in English.
- Commit only when asked. This is a public repository: no push, force push, tags pushed, or GitHub releases unless asked.
- No attribution lines (`Co-Authored-By` and the like) in commits, tags, or release notes.
- Run `scripts/release.sh` only with `--dry-run` unless asked to make a release.

## Workflow

- Work goes through OpenSpec changes: propose (proposal, spec deltas, design, tasks) → implement task by task with the stated verification → commit → archive with spec sync → release. The user decides how work is split into changes and usually asks to implement right after planning.
- Uncertain ideas (UI especially) are tried as a spike first: a `spike/<idea>` branch, quick code with `SPIKE:` comments, snapshots and a live build for the user to judge. Accepted spikes become a change (spike findings go into its design) and are brought to `main` cleaned up; the branch is deleted.
- MODIFIED requirements in a spec delta must keep every scenario of the current requirement (`openspec validate` refuses to drop one); to drop a scenario, REMOVE the requirement and ADD a renamed one.

## Build and test

```sh
xcodebuild -project kRecord.xcodeproj -scheme kRecord -derivedDataPath build/DerivedData build
xcodebuild -project kRecord.xcodeproj -scheme kRecord -derivedDataPath build/DerivedData -resultBundlePath build/last.xcresult test
xcrun xcresulttool get test-results summary --path build/last.xcresult   # failure messages; xcodebuild output omits them
rm -rf build/last.xcresult
```

- Without a development certificate, append `CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=` for ad-hoc signing (macOS then asks for audio permissions again after every rebuild).
- Build and test commands need the shell sandbox disabled (keychain and audio access).
- SourceKit diagnostics such as "Cannot find type … in scope" or "No such module 'Testing'" are false positives; trust `xcodebuild`.

## Versions and releases

- The version lives only in `Config/Version.xcconfig`; do not set `MARKETING_VERSION` or `CURRENT_PROJECT_VERSION` in the project file.
- Distributions are made with `scripts/release.sh <MAJOR.MINOR.PATCH>` (`--dry-run` to try), never by hand: it tests, versions, builds, verifies, commits, tags, and packages `build/dist/kRecord-<version>.zip`. Archive finished OpenSpec changes before releasing so the generated `CHANGELOG.md` section includes them.
- Version bump: new behavior → minor, fixes only → patch (pre-1.0).

## Checking the UI

- `ViewSnapshotTests` render every main window, Settings, and menu bar state to PNGs in `~/Library/Containers/com.kozian.kRecord/Data/tmp/kRecordSnapshots/` (the test host is sandboxed). Add `-testLanguage ru` to the test command for Russian. Look at the PNGs after UI changes.
- Run a single Swift Testing test with `"-only-testing:kRecordTests/<Suite>/<test>()"` (the parentheses are required, otherwise nothing runs and the run still reports success).
- DEBUG remote control of a running app: `open -n <Debug app> --args -KRDebugControl YES`, then `echo <command> > ~/Music/kRecord/.debug-command`; output in `~/Music/kRecord/debug-control.log`. Commands (`kRecord/Debug/DebugControl.swift`): `closeMainWindow`, `openSettings`, `openSettingsLikeMenuBar`, `hideMenuBarItem`, `showMenuBarItem`, `startRecording`, `stopRecording`, `logState` (windows, scroll views, active app, topmost window), `snapshotMainWindow` (draws the running main window with its frame and window buttons to `~/Music/kRecord/main-window.png`), `confirmAlert`, `cancelAlert`, `quit`. Settings for such runs can be set with `defaults write ~/Library/Containers/com.kozian.kRecord/Data/Library/Preferences/com.kozian.kRecord <key> …` while the app is not running; restore them afterwards.
- Without Screen Recording access, the window server does not list menu bar items and screenshots are not possible; ask the user to look at the screen for those checks.

## Verifying audio on real hardware

DEBUG builds have a headless recording harness (`kRecord/Debug/DebugRecording.swift`):

```sh
open -n build/DerivedData/Build/Products/Debug/kRecord.app --args -KRDebugRecord 10 \
  [-KRDebugSources all|mic|system] [-KRDebugSaveAsM4A NO] [-KRDebugSeparate YES] [-KRDebugEchoCancellation YES]
```

It records to `~/Music/kRecord/` through `RecordingSession` and the production capture → writer → finalizer pipeline and logs to `~/Music/kRecord/debug-recording.log`. Permission prompts and sound appear on the Mac's own screen and speakers, so ask the user to be at the Mac when a check needs them.

Tools in `scripts/hw/` (usage in each file):

- `audioctl.swift` — list inputs/outputs, switch the macOS default input, and create a temporary second input ("kRecordTest Input", an aggregate of the first input device) to test device switching without a second microphone; selecting it explicitly and letting it expire simulates an unplugged selected microphone.
- `make-clicks.py` + `afplay` — a click per second through the speakers; recorded in separate-files mode, `analyze-clicks.py` reports equal track lengths, lost system audio (click spacing below 1.0 s), and microphone/system click offsets.

## Code conventions

- Swift 6 language mode, strict concurrency, no default MainActor isolation. Real-time audio code (`AggregateIOContext.process`, `RingBuffer.write`, `LevelSnapshot.publish`) must not allocate, lock, or log.
- Apple frameworks only; no packages.
- Typed throws (`throws(CaptureError)` etc.) across the recording pipeline.
- Tests use Swift Testing; fakes live in `kRecordTests/Fakes/`.
- User-facing strings use `String(localized:)` or SwiftUI `Text("…")` literals. Command-line builds do not add new keys to `Localizable.xcstrings`; add keys (with `ru` translations, `"extractionState": "manual"`) to the catalog by hand, then run `python3 scripts/check-localization.py` after a build: it compares the strings the compiler extracted with the catalog.

## Architecture pointers

- `RecordingSession` (`@MainActor @Observable`) is the single source of truth for UI: `start()`, `stop()` (returns after saving, use it for quit), `state`, `formattedElapsedTime`, `levels`, `lastError` / `dismissError()`, `lastResult?.systemAudioSilent`, `canStart`. `AppModel` wires it with `SettingsStore`, `AudioDeviceCatalog`, `PermissionsManager`, and `QuitCoordinator`.
- Capture: `AggregateCaptureEngine` (default) and `VoiceProcessingCaptureEngine` (echo cancellation: voice-processing `AVAudioEngine` for the microphone plus a system-only aggregate, aligned by host time).
- `HomeDirectory.defaultRecordingsFolder` is the real `~/Music/kRecord/` (the sandbox's `NSHomeDirectory()` is the container).
- Settings are `UserDefaults` keys in `SettingsStore.Key`; booleans that default to on use `object(forKey:) as? Bool ?? true`.

## SwiftUI pitfalls found here

- A scene body in `App` does not track `@Observable` models; use `@AppStorage` on the same key to drive scene modifiers (`MenuBarExtra(isInserted:)`).
- A binding given to `MenuBarExtra(isInserted:)` is written back on every scene update; writing unchanged values into an observable store loops updates at 100% CPU.
- A menu-style `Picker` is never wider than its longest item, whatever `frame` it gets; align it instead of trying to stretch it.
- In a `.menu`-style `MenuBarExtra`, gestures on items never run; use `Button` actions. Bringing Settings in front of another app needs `NSApp.activate(ignoringOtherApps: true)` (`SettingsWindow.show`).
- `Localizable.xcstrings` keys are sorted case-insensitively, as Xcode writes them; keep that order when editing it by script.
