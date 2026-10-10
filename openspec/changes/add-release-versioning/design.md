# Design

## Context

`MARKETING_VERSION = 0.1` and `CURRENT_PROJECT_VERSION = 1` are set in four build configurations in `project.pbxproj` (app and tests, Debug and Release). Releases so far were built by hand with `xcodebuild … -configuration Release` and `ditto` into `build/dist/kRecord.zip`. OpenSpec changes are archived under `openspec/changes/archive/<date>-<name>/` with a `proposal.md` whose "What Changes" lists the user-visible changes.

## Goals / Non-Goals

**Goals:**
- One command that turns the current commit into a numbered, traceable, verified release zip.
- A changelog that writes itself from the OpenSpec history.

**Non-Goals:**
- Distribution channels or notarization.

## Decisions

### D1. Version file
`Config/Version.xcconfig` holds `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION`. All four build configurations use it as their base configuration, and the two settings are removed from the project file so the xcconfig is the only source. Between releases it keeps the last released numbers, so developer builds show the version they are based on.
- **Alternative:** a build-phase script that computes the build number at build time — needs script sandboxing exceptions and makes every developer build differ.

### D2. Build number = commit count of the release commit
The script writes `git rev-list --count HEAD` + 1 into the xcconfig, because the release commit that contains the change will be that commit; after committing it checks that the count matches. The number therefore grows with every release and identifies the commit.

### D3. Release order
1. Refuse when tracked files have uncommitted changes (untracked files are ignored), when the version is not `MAJOR.MINOR.PATCH`, when the tag exists, or when the version is not higher than the last tag.
2. Run the unit tests (skippable with `--skip-tests`).
3. Write the xcconfig and the changelog section.
4. Build the Release configuration into `build/DerivedData`, verify the code signature and that the built `Info.plist` carries exactly the version and build number.
5. Commit "Release <version>" (xcconfig and changelog), tag `v<version>` (annotated with the changelog section).
6. Package `build/dist/kRecord-<version>.zip` with `ditto`, write its SHA-256 next to it.
If any step before the commit fails, the script restores the xcconfig and changelog. `--dry-run` stops after step 4, restores the files, and still writes the zip with a `-dryrun` suffix for inspection.

### D4. Changelog from archived changes
`scripts/changelog.py` finds the change directories added under `openspec/changes/archive/` since the previous tag (all of them for the first release) and writes a `## <version> — <date>` section with one entry per change: its name and the top-level bullets of its proposal's "What Changes". New sections go on top of `CHANGELOG.md`.
- **Why:** proposals already describe each change for humans; the archive date marks when it shipped.

## Risks / Trade-offs

- [Signing needs the unlocked keychain over SSH] → The script stops with the build error and restores the files; the SSH unlock step is documented in `CLAUDE.md`.
- [A completed but unarchived change is missing from the changelog] → Archive changes before releasing; the script prints the list of active OpenSpec changes as a reminder.
