#!/usr/bin/env bash
# Ad-hoc signed .app in build/, no developer account required.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"
CONFIG="${1:-Release}"

command -v xcodegen >/dev/null || { echo "xcodegen missing: brew install xcodegen" >&2; exit 1; }

echo "==> xcodegen"
xcodegen generate --quiet

echo "==> build ($CONFIG)"
DERIVED="$ROOT/build/DerivedData"
xcodebuild \
    -scheme Belay \
    -configuration "$CONFIG" \
    -destination 'platform=macOS' \
    -derivedDataPath "$DERIVED" \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGNING_REQUIRED=YES \
    CODE_SIGNING_ALLOWED=YES \
    build | (xcbeautify 2>/dev/null || cat)

APP="$DERIVED/Build/Products/$CONFIG/Belay.app"
[ -d "$APP" ] || { echo "build produced no app at $APP" >&2; exit 1; }

rm -rf "$ROOT/build/Belay.app"
mkdir -p "$ROOT/build"
cp -R "$APP" "$ROOT/build/Belay.app"

# Re-sign what is embedded, inside out, with the same ad-hoc identity as the
# app. Sparkle ships pre-signed with its own team, and macOS refuses to load a
# framework whose Team ID differs from the process that maps it: an ad-hoc build
# has no team at all, so the mismatch is total and the app dies at launch with
# "Library not loaded ... have different Team IDs" before any of its own code
# runs. The release path does not hit this because it signs everything with one
# Developer ID.
# BELAY_SIGN_LOCAL names a real identity to use instead of ad-hoc, and the one
# thing it is for is testing updates. Sparkle refuses an update whose app does
# not carry the same code-signing identity as the app being replaced, which is
# the right rule and which no ad-hoc build can satisfy against a Developer ID
# release: "The update is improperly signed and could not be validated."
#
#   BELAY_SIGN_LOCAL="Developer ID Application" scripts/build-local.sh Debug
IDENTITY="${BELAY_SIGN_LOCAL:--}"

echo "==> re-sign everything inside ($IDENTITY)"
# Everything, not only the framework bundles. A Debug build keeps most of its
# code in `Belay.debug.dylib` beside the executable, and Xcode leaves a
# `__preview.dylib` there too. Signing the app with a real identity turns on
# Library Validation, which then refuses to load a dylib signed by somebody
# else: the app died at launch with "Library not loaded: @rpath/Belay.debug.dylib"
# and a crash report that blamed dyld. Observed 2026-08-17, the first time this
# script was asked for a Developer ID signature.
#
# Deepest first: signing a bundle seals what is inside it, so an inner helper
# signed afterwards invalidates the seal around it.
find "$ROOT/build/Belay.app" \
    \( -name "*.app" -o -name "*.xpc" -o -name "*.framework" -o -name "*.dylib" \) \
    -not -path "$ROOT/build/Belay.app" -print0 \
    | sort -rz \
    | xargs -0 -I{} codesign --force --sign "$IDENTITY" --options runtime --timestamp=none {} \
        >/dev/null 2>&1
# The lid helper is a bare executable, which the bundle patterns above cannot
# see, and it must be sealed before the app is: SMAppService checks its
# signature, and signing it after the app would break the app's own seal.
HELPER="$ROOT/build/Belay.app/Contents/MacOS/BelayLidHelper"
if [ -f "$HELPER" ]; then
    codesign --force --sign "$IDENTITY" --options runtime --timestamp=none \
        "$HELPER" >/dev/null 2>&1
fi
codesign --force --sign "$IDENTITY" --options runtime --timestamp=none \
    "$ROOT/build/Belay.app" >/dev/null 2>&1

echo "==> verify signature"
codesign --verify --deep --strict --verbose=2 "$ROOT/build/Belay.app"

# Nine copies of this bundle identifier were registered on the development Mac
# at one point, one of them at a path that no longer existed. Notification
# Center resolves the app icon through LaunchServices by identifier, so which
# copy wins is not a detail. Registering the fresh build makes it the newest
# claim rather than leaving it to whichever DerivedData copy was seen last.
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
[ -x "$LSREGISTER" ] && "$LSREGISTER" -f "$ROOT/build/Belay.app" 2>/dev/null || true

echo
echo "built: build/Belay.app"
echo "run:   open build/Belay.app"
echo "check: pmset -g assertions | grep -i belay"
