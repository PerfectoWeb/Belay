#!/usr/bin/env bash
# Cuts a notarized, stapled DMG of the direct build.
#
# WRITTEN, NEVER RUN. There is no Developer ID identity on the machine this was
# developed on (BLOCKERS.md B1), so none of this is proven. Read it before the
# first real release rather than trusting it.
#
# It refuses to start unless every prerequisite is present. Half a release —
# a signed app that was never notarized, a DMG with no stapled ticket — is
# worse than no release, because it looks finished.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# ---------------------------------------------------------------- placeholders
# PLACEHOLDER — BLOCKERS.md B1. Set BELAY_TEAM_ID in the environment or replace
# this literal. The script will not run while it is still ABCDE12345.
TEAM_ID="${BELAY_TEAM_ID:-ABCDE12345}"

# The name of the notarytool credential profile stored with
#   xcrun notarytool store-credentials BelayNotary \
#       --apple-id you@example.com --team-id "$TEAM_ID" --password <app-specific>
NOTARY_PROFILE="${BELAY_NOTARY_PROFILE:-BelayNotary}"

# Empty locally; CI stores the profile in a throwaway keychain and notarytool
# looks only in the login keychain unless it is told otherwise. Passed straight
# through to notarize.sh, which honours the same variable.
NOTARY_KEYCHAIN="${BELAY_NOTARY_KEYCHAIN:-}"

SIGN_IDENTITY="${BELAY_SIGN_IDENTITY:-Developer ID Application}"
# ------------------------------------------------------------------------------

SCHEME="Belay"
CONFIG="Release"
DIST="$ROOT/dist"
ARCHIVE="$DIST/Belay.xcarchive"
EXPORT_DIR="$DIST/export"
APP="$EXPORT_DIR/Belay.app"

usage() {
    cat <<'EOF'
release.sh - build, sign, notarize and package the direct build of Belay.

Usage: scripts/release.sh [--skip-notarize]

Produces dist/Belay-<version>.dmg, notarized and stapled.

Environment:
  BELAY_TEAM_ID         Apple Developer team ID. Required; the placeholder in
                        the script is rejected.
  BELAY_NOTARY_PROFILE  notarytool keychain profile name (default: BelayNotary)
  BELAY_NOTARY_KEYCHAIN keychain holding that profile. Unset means the login
                        keychain, which is right everywhere except CI.
  BELAY_SIGN_IDENTITY   codesign identity (default: "Developer ID Application")

Options:
      --skip-notarize   Sign and package only. The result is NOT shippable; it
                        exists so the packaging steps can be debugged without
                        burning notarization round trips.
  -h, --help            This text.

Exit status:
  0  a notarized, stapled DMG is in dist/
  1  a step failed
  2  a prerequisite is missing (nothing was built)
EOF
}

SKIP_NOTARIZE=0
while [ $# -gt 0 ]; do
    case "$1" in
        --skip-notarize) SKIP_NOTARIZE=1 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "unknown argument: $1" >&2; usage >&2; exit 2 ;;
    esac
    shift
done

die() { echo "release: $*" >&2; exit 2; }

# ------------------------------------------------------------------- preflight
echo "==> preflight"

[ "$TEAM_ID" != "ABCDE12345" ] || die "BELAY_TEAM_ID is still the placeholder. See BLOCKERS.md B1."

for tool in xcodegen xcodebuild create-dmg; do
    command -v "$tool" >/dev/null || case "$tool" in
        create-dmg) die "create-dmg is not installed. brew install create-dmg" ;;
        xcodegen)   die "xcodegen is not installed. brew install xcodegen" ;;
        *)          die "$tool is not on PATH. Install the Xcode command line tools." ;;
    esac
done

xcrun --find notarytool >/dev/null 2>&1 || die "notarytool is missing. Xcode 13 or newer is required."
xcrun --find stapler >/dev/null 2>&1 || die "stapler is missing. Xcode 13 or newer is required."

security find-identity -v -p codesigning | grep -q "$SIGN_IDENTITY" \
    || die "no '$SIGN_IDENTITY' identity in the keychain. Import it from developer.apple.com first."

if [ "$SKIP_NOTARIZE" -eq 0 ]; then
    PROFILE_AUTH=(--keychain-profile "$NOTARY_PROFILE")
    if [ -n "$NOTARY_KEYCHAIN" ]; then
        PROFILE_AUTH+=(--keychain "$NOTARY_KEYCHAIN")
    fi
    # A profile is preferred but not required: notarize.sh also accepts the API
    # key in .secrets/. Only fail here when neither is available, so that a
    # machine set up the .secrets/ way still gets past preflight.
    if ! xcrun notarytool history "${PROFILE_AUTH[@]}" >/dev/null 2>&1 \
        && [ ! -f "$ROOT/.secrets/appstoreconnect.env" ]; then
        die "no notarization credentials. Either store a profile:
    xcrun notarytool store-credentials '$NOTARY_PROFILE' --key <p8> --key-id <id> --issuer <issuer>
  or put the key and ids in .secrets/appstoreconnect.env. See BLOCKERS.md B6."
    fi
fi

# The MAS target must never end up in a Developer ID archive, and Sparkle must
# never end up in the MAS one. Cheap to assert, expensive to discover later.
grep -q 'Belay-MAS' "$ROOT/project.yml" || die "project.yml has no Belay-MAS target; this is not the tree release.sh was written for."

rm -rf "$DIST"
mkdir -p "$DIST"

# --------------------------------------------------------------------- archive
echo "==> xcodegen"
xcodegen generate --quiet

echo "==> archive ($SCHEME, $CONFIG)"
xcodebuild archive \
    -scheme "$SCHEME" \
    -configuration "$CONFIG" \
    -destination 'generic/platform=macOS' \
    -archivePath "$ARCHIVE" \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="$SIGN_IDENTITY" \
    | (xcbeautify 2>/dev/null || tail -20)

[ -d "$ARCHIVE" ] || die "archive step produced nothing at $ARCHIVE"

# ---------------------------------------------------------------------- export
cat > "$DIST/ExportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key><string>developer-id</string>
    <key>teamID</key><string>$TEAM_ID</string>
    <key>signingStyle</key><string>manual</string>
    <key>destination</key><string>export</string>
</dict>
</plist>
EOF

echo "==> export"
xcodebuild -exportArchive \
    -archivePath "$ARCHIVE" \
    -exportOptionsPlist "$DIST/ExportOptions.plist" \
    -exportPath "$EXPORT_DIR" \
    | (xcbeautify 2>/dev/null || tail -20)

[ -d "$APP" ] || die "export produced no app at $APP"

echo "==> verify signature"
codesign --verify --deep --strict --verbose=2 "$APP"
codesign -d --entitlements - --xml "$APP" >/dev/null

# Hardened Runtime is not optional for notarization and its absence is only
# discovered by the notary service, twenty minutes later.
#
# Read into a variable rather than piped into `grep -q`. Under `set -o
# pipefail` that pipeline fails even when the match succeeds: `grep -q` exits
# the moment it finds the line, `codesign` gets SIGPIPE, and the pipeline
# reports 141. The first real run of this script died here on a correctly
# hardened app.
SIGNING="$(codesign -d --verbose=2 "$APP" 2>&1 || true)"
case "$SIGNING" in
    *"flags="*"runtime"*) ;;
    *) die "the exported app is not hardened-runtime signed; notarization would be rejected" ;;
esac

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
DMG="$DIST/Belay-$VERSION.dmg"

# ------------------------------------------------------------------------- dmg
echo "==> dmg"

# Stage the app on its own. `-exportArchive` leaves DistributionSummary.plist,
# ExportOptions.plist and Packaging.log in the export directory, and pointing
# create-dmg at it ships all three inside the disk image.
DMG_STAGE="$(mktemp -d)"
trap 'rm -rf "$DMG_STAGE"' EXIT
cp -R "$EXPORT_DIR/Belay.app" "$DMG_STAGE/"

# The window is 640x420 points. Any background art has to match that exactly,
# in points, or Finder scales it and the icon positions below stop landing
# where the picture expects them.
DMG_ARGS=(
    --volname "Belay $VERSION"
    --window-size 640 420
    --icon-size 96
    --icon "Belay.app" 170 220
    --app-drop-link 470 220
    --no-internet-enable
)

# The icon of the mounted volume, which is what Finder shows in the sidebar and
# on the desktop. Without it a disk image gets the generic grey arrow, which is
# why some installers look unfinished before they have even been opened. The
# app's own icon is the right one; it is built already, so nothing to draw.
VOLICON="$EXPORT_DIR/Belay.app/Contents/Resources/AppIcon.icns"
[ -f "$VOLICON" ] && DMG_ARGS+=(--volicon "$VOLICON")

# Optional, and only used when it exists, so a release never waits on artwork.
# Make it with scripts/make-dmg-background.sh, which pairs the 1x and 2x
# exports into the one file Finder needs.
DMG_BACKGROUND="$ROOT/Promo/dmg-background.tiff"
if [ -f "$DMG_BACKGROUND" ]; then
    DMG_ARGS+=(--background "$DMG_BACKGROUND")
else
    echo "note: no $DMG_BACKGROUND; packaging on the plain window"
fi

# create-dmg lays the window out by driving Finder over Apple Events, so it
# needs Automation permission for whatever is running this script. Denied, it
# fails late and leaves its read-write staging image behind in dist/, which
# looks like a build product and is not one.
if ! create-dmg "${DMG_ARGS[@]}" "$DMG" "$DMG_STAGE"; then
    rm -f "$DIST"/rw.*.dmg
    die "create-dmg failed. If it said 'Not authorized to send Apple events to
Finder', grant Automation permission in System Settings, Privacy & Security,
Automation, and tick Finder under whichever app is running this script."
fi

[ -f "$DMG" ] || die "create-dmg exited 0 but produced no $DMG"

codesign --sign "$SIGN_IDENTITY" --timestamp "$DMG"

# -------------------------------------------------------------------- notarize
if [ "$SKIP_NOTARIZE" -eq 1 ]; then
    echo
    echo "NOT NOTARIZED (--skip-notarize). $DMG will show Gatekeeper warnings and must not be published."
    exit 0
fi

"$SCRIPT_DIR/notarize.sh" "$DMG"

echo
echo "released: $DMG"
echo "next:     scripts/sign-update.sh to add it to the appcast"
