#!/usr/bin/env bash
# Cuts a notarized, stapled DMG of the direct build.
#
# Run for real on 2026-08-13: this script built, signed, notarized, stapled and
# packaged the v1.0.0 DMG that shipped. The Developer ID identity is in the
# login keychain (docs/BLOCKERS.md B1) and notarization is closed (B6).
#
# Three faults only showed up when it was finally run, and each is commented
# where it was found rather than here: get-task-allow surviving into a release
# archive, an attempt to staple a zip, and a hardened-runtime check that failed
# on correctly hardened apps because of pipefail. Reading a release script is
# not the same as running one.
#
# It refuses to start unless every prerequisite is present. Half a release —
# a signed app that was never notarized, a DMG with no stapled ticket — is
# worse than no release, because it looks finished.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# ---------------------------------------------------------------- placeholders
# PLACEHOLDER — docs/BLOCKERS.md B1. Set BELAY_TEAM_ID in the environment or replace
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

[ "$TEAM_ID" != "ABCDE12345" ] || die "BELAY_TEAM_ID is still the placeholder. See docs/BLOCKERS.md B1."

for tool in xcodegen xcodebuild; do
    command -v "$tool" >/dev/null || case "$tool" in
        xcodegen) die "xcodegen is not installed. brew install xcodegen" ;;
        *)        die "$tool is not on PATH. Install the Xcode command line tools." ;;
    esac
done

# dmgbuild is a Python package, so it can be on PATH, in a virtualenv, or
# reachable as a module. Accept any of them rather than insisting on one shape
# of install.
#
# Held as an array. It can be one word or three, and a three-word command stored
# in a plain string and then run as "$DMGBUILD" is a single filename with spaces
# in it, which is not a thing.
if command -v dmgbuild >/dev/null; then
    DMGBUILD=("$(command -v dmgbuild)")
elif python3 -c 'import dmgbuild' 2>/dev/null; then
    DMGBUILD=(python3 -m dmgbuild)
else
    die "dmgbuild is not installed. pipx install 'dmgbuild>=1.6.7'"
fi

# Check the defect, not the version number. Before 1.6.7 dmgbuild wrote a pBBk
# bookmark into the .DS_Store alongside the alias, and Finder from macOS 26.2
# onwards silently draws no background at all when it finds one. The window
# size and the icon positions from the same file still come out right, so the
# failure looks like bad artwork rather than a bad builder, and cost an
# afternoon here before it was found. dmgbuild has no --version flag, so ask
# the interpreter that owns it whether the offending key is still in its source.
if [ "${#DMGBUILD[@]}" -gt 1 ]; then
    DMGBUILD_PY=(python3)
else
    # A shebang is a command line, not a path. pipx writes
    # `#!<venv>/bin/python -E`, and taking the whole line as one word sends the
    # shell looking for a file called "python -E". That is what the release
    # workflow died on the first time its credentials were good enough to get
    # this far, and it never showed up locally because a plain virtualenv
    # writes a shebang with no flags on it.
    read -r -a DMGBUILD_PY <<<"$(head -1 "${DMGBUILD[0]}" | sed 's|^#!||')"
fi
[ -n "${DMGBUILD_PY[0]:-}" ] && [ -x "${DMGBUILD_PY[0]}" ] || DMGBUILD_PY=(python3)

"${DMGBUILD_PY[@]}" -c "
import inspect, sys
import dmgbuild.core
sys.exit(1 if 'pBBk' in inspect.getsource(dmgbuild.core) else 0)
" || die "this dmgbuild still writes the pBBk bookmark, which leaves the disk
image with no background on macOS 26.2 and later. Upgrade it:
    pipx install --force 'dmgbuild>=1.6.7'"

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
  or put the key and ids in .secrets/appstoreconnect.env. See docs/BLOCKERS.md B6."
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

# ------------------------------------------------------- notarize the app first
# The app is notarized and stapled before it goes into the disk image, and the
# disk image is notarized and stapled after. Two round trips, on purpose.
#
# Stapling only the DMG leaves the copy in /Applications with no ticket of its
# own. It still launches, because Gatekeeper asks Apple over the network and is
# told the app is notarized — but a first launch with no network, on a plane or
# behind a captive portal, has nothing to ask and shows the warning instead. A
# ticket inside the app answers the question locally and for ever.
if [ "$SKIP_NOTARIZE" -eq 0 ]; then
    echo "==> notarize the app"
    APP_ZIP="$DIST/Belay-app-for-notarization.zip"
    /usr/bin/ditto -c -k --keepParent "$APP" "$APP_ZIP"

    # notarize.sh knows a zip cannot hold a ticket and staples the bundle
    # instead, but it works that bundle out from the zip's name. This zip is
    # named for its errand rather than for the app, so tell it directly.
    BELAY_STAPLE_APP="$APP" "$SCRIPT_DIR/notarize.sh" "$APP_ZIP"
    rm -f "$APP_ZIP"

    xcrun stapler validate "$APP" \
        || die "the app was notarized but the ticket did not staple to it"
fi

# ------------------------------------------------------------------------- dmg
echo "==> dmg"

# The window, its background and where the two icons sit are all in
# scripts/dmg-settings.py, next to the measurements they came from.
#
# dmgbuild rather than create-dmg. create-dmg arranges the window by driving
# Finder over Apple Events, which needs Automation permission: a build machine
# has no way to grant it, and on a laptop it can be revoked between one release
# and the next, which is exactly what happened here. dmgbuild writes the
# .DS_Store itself and never talks to Finder, so the same command works over
# ssh and in CI.
rm -f "$DMG"
"${DMGBUILD[@]}" -s "$ROOT/scripts/dmg-settings.py" \
    -D root="$ROOT" -D app="$EXPORT_DIR/Belay.app" \
    "Belay $VERSION" "$DMG" \
    || die "dmgbuild failed"

[ -f "$DMG" ] || die "dmgbuild exited 0 but produced no $DMG"

codesign --sign "$SIGN_IDENTITY" --timestamp "$DMG"

# -------------------------------------------------------------------- notarize
if [ "$SKIP_NOTARIZE" -eq 1 ]; then
    echo
    echo "NOT NOTARIZED (--skip-notarize). $DMG will show Gatekeeper warnings and must not be published."
    exit 0
fi

"$SCRIPT_DIR/notarize.sh" "$DMG"

# A second copy under a name that never changes. The versioned name is what
# people should keep on disk, but a download button on a web page cannot know
# next release's version, and /releases/latest/download/Belay.dmg can.
cp "$DMG" "$DIST/Belay.dmg"

echo
echo "released: $DMG"
echo "          $DIST/Belay.dmg — upload this one too, it is what the site links to:"
echo "          gh release upload <tag> $DIST/Belay.dmg --clobber"
echo "next:     scripts/sign-update.sh to add it to the appcast"
