# Developing kRecord

## Requirements

- Apple silicon Mac with macOS 15 or later
- Xcode 27
- Apple frameworks only: there are no package dependencies to fetch.

## Repository layout

| Path | Contents |
|---|---|
| `kRecord/App` | App delegate, `AppModel` wiring, quit handling |
| `kRecord/Audio` | Capture engines (Core Audio process tap + aggregate device, voice-processing path), device monitoring, ring buffer, levels |
| `kRecord/Recording` | `RecordingSession` state machine, AAC writer, `.m4a` finalizer, file naming, storage guard |
| `kRecord/Settings` | Settings store, folder bookmarks, device catalog, permissions |
| `kRecord/Views` | Main window, Settings, menu bar |
| `kRecord/Debug` | DEBUG-only remote control and headless recording harness |
| `kRecordTests` | Swift Testing unit tests and view snapshots; fakes in `Fakes/` |
| `openspec` | Behavior specs (`specs/`) and the planned or finished changes with their designs (`changes/`) |
| `docs` | Manual QA checklist, spec coverage, screenshot |
| `scripts` | Release, changelog, localization check, app icon; hardware test tools in `scripts/hw` |
| `Config/Version.xcconfig` | Version and build number |

Before changing audio code, read the `design.md` of `openspec/changes/archive/2026-10-10-add-core-recording` and `2026-10-10-fix-device-switching-and-settings-focus`: they record hardware findings that the code depends on.

## Build and test

Open `kRecord.xcodeproj` in Xcode and press ⌘R. Signing uses your own development team: select it in the target's *Signing & Capabilities* tab.

From the command line:

```sh
xcodebuild -project kRecord.xcodeproj -scheme kRecord -derivedDataPath build/DerivedData build
xcodebuild -project kRecord.xcodeproj -scheme kRecord -derivedDataPath build/DerivedData -resultBundlePath build/last.xcresult test
xcrun xcresulttool get test-results summary --path build/last.xcresult   # failure messages
rm -rf build/last.xcresult
```

The app is written to `build/DerivedData/Build/Products/Debug/kRecord.app`.

Without a development certificate, build with ad-hoc signing by appending `CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=`. The app runs, but macOS asks for microphone and system audio permissions again after every rebuild, because permissions are tied to the signature.

Run a single test with `"-only-testing:kRecordTests/<Suite>/<test>()"`; the parentheses are required.

## Checking the UI

- `ViewSnapshotTests` render the main window, Settings, and menu bar states to PNG files in `~/Library/Containers/com.kozian.kRecord/Data/tmp/kRecordSnapshots/`. Add `-testLanguage ru` to the test command for Russian.
- A DEBUG build started with `--args -KRDebugControl YES` accepts commands written to `~/Music/kRecord/.debug-command` (open windows, start and stop recording, log window state, draw the main window to a PNG); see `kRecord/Debug/DebugControl.swift`.

## Checking audio

- A DEBUG build started with `--args -KRDebugRecord <seconds>` records through the production pipeline without UI and logs to `~/Music/kRecord/debug-recording.log`; options are listed in `kRecord/Debug/DebugRecording.swift`.
- `scripts/hw/` has tools to switch input devices, simulate a second or unplugged microphone, and measure lost audio and microphone/system alignment with a click track. Usage is in each file.
- Hardware-dependent behavior is checked by hand with [docs/manual-qa-checklist.md](docs/manual-qa-checklist.md); [docs/spec-coverage.md](docs/spec-coverage.md) maps each spec scenario to its check.

## Localization

The interface is in English and Russian (`kRecord/Localizable.xcstrings`, `kRecord/InfoPlist.xcstrings`). Command-line builds do not add new strings to the catalog: add them by hand with a Russian translation, then run `python3 scripts/check-localization.py` after a build to compare the catalog with the strings the compiler extracted.

## App icon

`swift scripts/make-app-icon.swift <artwork.png>` builds every size of `AppIcon.appiconset` from one square artwork image.

## Workflow

Changes are planned with [OpenSpec](https://github.com/Fission-AI/OpenSpec): a proposal, spec deltas, a design, and tasks per change; after implementation the change is archived and its deltas merged into `openspec/specs/`. Rules for coding agents are in [AGENTS.md](AGENTS.md).

## Releases

Versions follow semantic versioning (`MAJOR.MINOR.PATCH`, set only in `Config/Version.xcconfig`); the build number is the git commit count of the release commit. To make a release, archive the finished OpenSpec changes, commit, and run:

```sh
scripts/release.sh 0.5.0            # add --dry-run to try it without committing
```

It runs the tests, sets the version, adds a section to [CHANGELOG.md](CHANGELOG.md) from the archived changes, builds and verifies the signed Release app, commits "Release 0.5.0", tags `v0.5.0`, and writes `build/dist/kRecord-0.5.0.zip` with a `.sha256` checksum. The app is not notarized.
