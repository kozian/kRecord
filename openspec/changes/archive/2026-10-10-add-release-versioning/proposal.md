# Proposal

## Why

Builds handed to testers all say version 0.1 (1) and are all packaged as `kRecord.zip`, so nobody can tell which build a bug report is about, and there is no record of what each build contains.

## What Changes

- Version numbers follow semantic versioning: the marketing version (`CFBundleShortVersionString`, e.g. `0.2.0`) and a build number (`CFBundleVersion`) that only grows. The build number is the git commit count of the release commit, so each build maps to exactly one commit.
- Both numbers live in `Config/Version.xcconfig` instead of the project file.
- `scripts/release.sh <version>` produces a release in one step: checks for uncommitted changes, runs the tests, sets the version and build number, updates `CHANGELOG.md` from the OpenSpec changes archived since the previous release, builds and verifies the signed Release app, commits "Release <version>", tags `v<version>`, and writes `build/dist/kRecord-<version>.zip` with a SHA-256 checksum. A `--dry-run` mode does everything except the commit and tag.
- First release: 0.2.0.

Out of scope: notarization, publishing (GitHub releases, update feeds), automatic version bump suggestions.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

None: the app's behavior does not change (`skip_specs: true`). The version is shown by the standard "About kRecord" panel as before.

## Impact

- `kRecord.xcodeproj/project.pbxproj` (configurations based on `Config/Version.xcconfig`), new `Config/Version.xcconfig`, `scripts/release.sh`, `scripts/changelog.py`, new `CHANGELOG.md`, `README.md` and `CLAUDE.md` (release instructions).
- Git: release commits and `v*` tags.
