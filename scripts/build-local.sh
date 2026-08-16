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
if [ -d "$ROOT/build/Belay.app/Contents/Frameworks" ]; then
    echo "==> re-sign embedded frameworks (ad-hoc)"
    # Deepest first: signing a bundle seals what is inside it, so an inner
    # helper signed afterwards invalidates the seal around it.
    find "$ROOT/build/Belay.app/Contents/Frameworks" \
        \( -name "*.app" -o -name "*.xpc" -o -name "*.framework" \) -print0 \
        | sort -rz \
        | xargs -0 -I{} codesign --force --sign - --timestamp=none {} >/dev/null 2>&1
    codesign --force --sign - --timestamp=none "$ROOT/build/Belay.app" >/dev/null 2>&1
fi

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
