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
    -scheme Vigil \
    -configuration "$CONFIG" \
    -destination 'platform=macOS' \
    -derivedDataPath "$DERIVED" \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGNING_REQUIRED=YES \
    CODE_SIGNING_ALLOWED=YES \
    build | (xcbeautify 2>/dev/null || cat)

APP="$DERIVED/Build/Products/$CONFIG/Vigil.app"
[ -d "$APP" ] || { echo "build produced no app at $APP" >&2; exit 1; }

rm -rf "$ROOT/build/Vigil.app"
mkdir -p "$ROOT/build"
cp -R "$APP" "$ROOT/build/Vigil.app"

echo "==> verify signature"
codesign --verify --deep --strict --verbose=2 "$ROOT/build/Vigil.app"

echo
echo "built: build/Vigil.app"
echo "run:   open build/Vigil.app"
echo "check: pmset -g assertions | grep -i vigil"
