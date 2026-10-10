# kRecord

A minimal native macOS recorder for meetings: it captures your microphone and all system audio at the same time and saves them to a file automatically. Built only on Apple system frameworks (Core Audio, AVFoundation, SwiftUI); no third-party dependencies, no virtual audio drivers, no Screen Recording permission.

## Requirements

- macOS 15 or later
- Apple silicon Mac (M1 or newer)
- Xcode 27 to build

## Build

Open `kRecord.xcodeproj` in Xcode and press ⌘R. Signing uses your own development team: select it in the target's *Signing & Capabilities* tab.

From the command line:

```sh
xcodebuild -project kRecord.xcodeproj -scheme kRecord -derivedDataPath build/DerivedData build
```

The app is written to `build/DerivedData/Build/Products/Debug/kRecord.app`.

Without a development certificate, build with ad-hoc signing instead. The app runs, but macOS will ask for microphone and system audio permissions again after every rebuild:

```sh
xcodebuild -project kRecord.xcodeproj -scheme kRecord -derivedDataPath build/DerivedData \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= build
```

Run the unit tests by replacing `build` with `test` in either command.

## Releases

Versions follow semantic versioning (`MAJOR.MINOR.PATCH`, set in `Config/Version.xcconfig`); the build number is the git commit count of the release commit. To make a release, archive the finished OpenSpec changes, commit, and run:

```sh
scripts/release.sh 0.3.0            # add --dry-run to try it without committing
```

It runs the tests, sets the version, adds a section to [CHANGELOG.md](CHANGELOG.md) from the archived changes, builds and verifies the signed Release app, commits "Release 0.3.0", tags `v0.3.0`, and writes `build/dist/kRecord-0.3.0.zip` with a `.sha256` checksum.

On another Mac, unzip the app into Applications and allow it once in System Settings → Privacy & Security ("Open Anyway"), since it is not notarized.

## Manual testing

Hardware-dependent behavior is checked by hand with [docs/manual-qa-checklist.md](docs/manual-qa-checklist.md).

## License

[MIT](LICENSE) © 2026 Konstantin Kuznetsov
