# Tasks

## 1. Version file

- [x] 1.1 Add `Config/Version.xcconfig` (version 0.1, build 1 until the first release) as the base configuration of all four build configurations and remove the version settings from `project.pbxproj`; verify the app and tests still build and the built `Info.plist` shows the values from the xcconfig

## 2. Release tooling

- [x] 2.1 Write `scripts/changelog.py` (D4); verify it prints a section listing the archived changes for a first release, and an empty section when nothing was archived since a given tag
- [x] 2.2 Write `scripts/release.sh` (D2, D3) with `--dry-run` and `--skip-tests`; verify a dry run for 0.2.0 builds a correctly versioned app, leaves the working tree unchanged, and refuses a dirty tree, an invalid version, and an existing tag
- [x] 2.3 Document releasing in `README.md` and `CLAUDE.md`; verify the documented command is the one the script accepts

## 3. First release

- [x] 3.1 Archive completed OpenSpec changes, then release 0.2.0 with the script; verify the tag `v0.2.0`, the release commit, `CHANGELOG.md`, `build/dist/kRecord-0.2.0.zip` with a matching SHA-256, and that the unpacked app reports 0.2.0 with the commit-count build number and a valid signature
