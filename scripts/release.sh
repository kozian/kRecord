#!/bin/bash
# Builds a numbered kRecord release from the current commit.
#
#     scripts/release.sh <MAJOR.MINOR.PATCH> [--dry-run] [--skip-tests]
#
# Checks the working tree, runs the tests, writes the version and build number to
# Config/Version.xcconfig, adds a CHANGELOG.md section from the OpenSpec changes archived since
# the previous release, builds and verifies the signed Release app, commits "Release <version>",
# tags v<version>, and writes build/dist/kRecord-<version>.zip with its SHA-256.
# --dry-run stops before the commit, restores the files, and writes kRecord-<version>-dryrun.zip.
set -euo pipefail

cd "$(dirname "$0")/.."

usage() { echo "usage: scripts/release.sh <MAJOR.MINOR.PATCH> [--dry-run] [--skip-tests]" >&2; exit 2; }
fail() { echo "release: $*" >&2; exit 1; }

VERSION=""
DRY_RUN=0
SKIP_TESTS=0
for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=1 ;;
        --skip-tests) SKIP_TESTS=1 ;;
        -*) usage ;;
        *) [[ -z "$VERSION" ]] || usage; VERSION="$arg" ;;
    esac
done
[[ -n "$VERSION" ]] || usage
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "version must be MAJOR.MINOR.PATCH, got '$VERSION'"

TAG="v$VERSION"
XCCONFIG="Config/Version.xcconfig"
CHANGELOG="CHANGELOG.md"
DERIVED="build/DerivedData"
APP="$DERIVED/Build/Products/Release/kRecord.app"
DIST="build/dist"

# 1. Preconditions.
git diff --quiet && git diff --cached --quiet || fail "tracked files have uncommitted changes; commit or stash them first"
git rev-parse -q --verify "refs/tags/$TAG" >/dev/null && fail "tag $TAG already exists"
PREVIOUS_TAG="$(git tag --list 'v*' --sort=-v:refname | head -n 1)"
if [[ -n "$PREVIOUS_TAG" ]]; then
    HIGHEST="$(printf '%s\n%s\n' "${PREVIOUS_TAG#v}" "$VERSION" | sort -V | tail -n 1)"
    [[ "$HIGHEST" == "$VERSION" ]] || fail "$VERSION is not higher than the previous release $PREVIOUS_TAG"
fi
echo "Releasing kRecord $VERSION (previous release: ${PREVIOUS_TAG:-none})"
if command -v openspec >/dev/null; then
    echo "Active OpenSpec changes (archive completed ones first so they appear in the changelog):"
    openspec list 2>/dev/null | sed -n '2,$p' || true
fi

# 2. Tests.
if [[ "$SKIP_TESTS" == 0 ]]; then
    echo "Running tests..."
    rm -rf build/release-tests.xcresult
    xcodebuild -project kRecord.xcodeproj -scheme kRecord -derivedDataPath "$DERIVED" \
        -resultBundlePath build/release-tests.xcresult test >build/release-tests.log 2>&1 \
        || fail "tests failed; see build/release-tests.log and build/release-tests.xcresult"
    echo "Tests passed."
fi

# 3. Version and changelog, restored unless the release commit is made.
BUILD_NUMBER=$(( $(git rev-list --count HEAD) + 1 ))
BACKUP="$(mktemp -d)"
cp "$XCCONFIG" "$BACKUP/"
[[ -f "$CHANGELOG" ]] && cp "$CHANGELOG" "$BACKUP/"
COMMITTED=0
restore() {
    if [[ "$COMMITTED" == 0 ]]; then
        cp "$BACKUP/Version.xcconfig" "$XCCONFIG"
        if [[ -f "$BACKUP/$CHANGELOG" ]]; then cp "$BACKUP/$CHANGELOG" "$CHANGELOG"; else rm -f "$CHANGELOG"; fi
    fi
    rm -rf "$BACKUP"
}
trap restore EXIT

sed -i '' -E "s/^MARKETING_VERSION = .*/MARKETING_VERSION = $VERSION/; s/^CURRENT_PROJECT_VERSION = .*/CURRENT_PROJECT_VERSION = $BUILD_NUMBER/" "$XCCONFIG"
SECTION="$(python3 scripts/changelog.py "$VERSION" ${PREVIOUS_TAG:+--since "$PREVIOUS_TAG"})"
{
    echo "# Changelog"
    echo
    echo "Versions follow semantic versioning; the build number is the git commit count of the release commit."
    echo
    echo "$SECTION"
    if [[ -f "$BACKUP/$CHANGELOG" ]] && grep -q '^## ' "$BACKUP/$CHANGELOG"; then
        # Older sections: everything from the first "## " heading of the previous file.
        echo
        sed -n '/^## /,$p' "$BACKUP/$CHANGELOG"
    fi
} >"$CHANGELOG"

# 4. Build and verify.
echo "Building $VERSION ($BUILD_NUMBER)..."
xcodebuild -project kRecord.xcodeproj -scheme kRecord -configuration Release -derivedDataPath "$DERIVED" \
    clean build >build/release-build.log 2>&1 || fail "Release build failed; see build/release-build.log"
codesign --verify --deep --strict "$APP" || fail "code signature of $APP is not valid"
BUILT_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
BUILT_NUMBER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")"
[[ "$BUILT_VERSION" == "$VERSION" && "$BUILT_NUMBER" == "$BUILD_NUMBER" ]] \
    || fail "built app reports $BUILT_VERSION ($BUILT_NUMBER), expected $VERSION ($BUILD_NUMBER)"

mkdir -p "$DIST"
if [[ "$DRY_RUN" == 1 ]]; then
    ZIP="$DIST/kRecord-$VERSION-dryrun.zip"
    rm -f "$ZIP"
    ditto -c -k --keepParent "$APP" "$ZIP"
    echo "Dry run: built $VERSION ($BUILD_NUMBER), wrote $ZIP; version files restored, nothing committed."
    echo "Changelog section that would be added:"
    echo "$SECTION"
    exit 0
fi

# 5. Commit and tag.
git add "$XCCONFIG" "$CHANGELOG"
git commit -q -m "Release $VERSION"
COMMITTED=1
[[ "$(git rev-list --count HEAD)" == "$BUILD_NUMBER" ]] || fail "release commit is #$(git rev-list --count HEAD), expected #$BUILD_NUMBER"
git tag -a "$TAG" -m "kRecord $VERSION ($BUILD_NUMBER)"$'\n\n'"$SECTION"

# 6. Package.
ZIP="$DIST/kRecord-$VERSION.zip"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
(cd "$DIST" && shasum -a 256 "kRecord-$VERSION.zip" >"kRecord-$VERSION.zip.sha256")
echo "Released kRecord $VERSION ($BUILD_NUMBER): tag $TAG, $ZIP"
cat "$ZIP.sha256"
