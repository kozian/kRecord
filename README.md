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

## Manual testing

Hardware-dependent behavior is checked by hand with [docs/manual-qa-checklist.md](docs/manual-qa-checklist.md).
