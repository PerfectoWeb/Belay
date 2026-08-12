#!/usr/bin/env bash
# Proves the two things about the App Store build that a human reviewer will
# check and that no unit test can:
#
#   1. it is sandboxed, with exactly the entitlements docs/06 lists, and it does
#      NOT have com.apple.security.network.client
#   2. there is no trace of Sparkle in it — Apple rejects third-party updaters,
#      and the direct build is the one that has one
#
# docs/08 asks for (2) as a CI step specifically. CI calls this script.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Release on purpose. A Debug build puts almost all of the code in a separate
# .debug.dylib, so auditing the main executable there proves close to nothing,
# and Debug also carries get-task-allow, which never ships.
CONFIG="${BELAY_MAS_CONFIG:-Release}"
DERIVED="$ROOT/build/DerivedData-MAS"
APP=""
BUILD=1

usage() {
    cat <<'EOF'
verify-mas-build.sh - entitlement and no-Sparkle audit of the Belay-MAS build.

Usage: scripts/verify-mas-build.sh [--app <path>] [--config <Debug|Release>]

With no arguments it builds the Belay-MAS scheme ad-hoc signed into
build/DerivedData-MAS and audits the result. --app skips the build and audits a
bundle you already have.

Exit status:
  0  sandboxed with the expected entitlements, no network.client, no Sparkle
  1  an audit failed
  2  a prerequisite is missing
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --app) APP="${2:?--app needs a path}"; BUILD=0; shift ;;
        --config) CONFIG="${2:?--config needs a value}"; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "unknown argument: $1" >&2; usage >&2; exit 2 ;;
    esac
    shift
done

fail() { echo "FAIL: $*" >&2; FAILED=1; }
pass() { echo "  ok  $*"; }
FAILED=0

if [ "$BUILD" -eq 1 ]; then
    command -v xcodegen >/dev/null || { echo "xcodegen missing: brew install xcodegen" >&2; exit 2; }
    xcodegen generate --quiet
    echo "==> build Belay-MAS ($CONFIG)"
    xcodebuild \
        -scheme Belay-MAS \
        -configuration "$CONFIG" \
        -destination 'platform=macOS' \
        -derivedDataPath "$DERIVED" \
        CODE_SIGN_IDENTITY="-" \
        CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
        build | (xcbeautify 2>/dev/null || tail -5)

    PRODUCT="$(xcodebuild -scheme Belay-MAS -configuration "$CONFIG" -destination 'platform=macOS' \
        -showBuildSettings 2>/dev/null | awk '/ FULL_PRODUCT_NAME =/ { print $3; exit }')"
    APP="$DERIVED/Build/Products/$CONFIG/$PRODUCT"
fi

[ -d "$APP" ] || { echo "no app bundle at $APP" >&2; exit 2; }
BINARY="$APP/Contents/MacOS/$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP/Contents/Info.plist")"
[ -f "$BINARY" ] || { echo "no executable at $BINARY" >&2; exit 2; }

echo
echo "==> entitlements ($APP)"
ENTS="$(codesign -d --entitlements - --xml "$APP" 2>/dev/null | plutil -convert xml1 -o - -)"
echo "$ENTS"

has_entitlement() {
    /usr/libexec/PlistBuddy -c "Print :$1" /dev/stdin <<<"$ENTS" 2>/dev/null
}

echo
echo "==> required entitlements"
for key in \
    com.apple.security.app-sandbox \
    com.apple.security.files.user-selected.read-write \
    com.apple.security.files.bookmarks.app-scope \
    com.apple.security.network.server
do
    if [ "$(has_entitlement "$key")" = "true" ]; then
        pass "$key"
    else
        fail "$key is missing or not true in the MAS build"
    fi
done

echo
echo "==> forbidden entitlements"
# The absence of network.client is the answer we give App Review about the
# loopback socket. It is a product claim, not a build detail.
for key in \
    com.apple.security.network.client \
    com.apple.security.cs.disable-library-validation \
    com.apple.security.cs.allow-unsigned-executable-memory
do
    if [ -n "$(has_entitlement "$key")" ]; then
        fail "$key is present in the MAS build"
    else
        pass "no $key"
    fi
done

# A plain `xcodebuild build` injects get-task-allow whatever the configuration
# says; only archive/export strips it. The build above therefore asks for it not
# to be injected, so what is audited here is exactly the entitlements file.
if [ -n "$(has_entitlement com.apple.security.get-task-allow)" ]; then
    fail "com.apple.security.get-task-allow is present; this bundle would be rejected on upload"
fi

echo
echo "==> no Sparkle"
if [ -d "$APP/Contents/Frameworks" ] && ls "$APP/Contents/Frameworks" 2>/dev/null | grep -qi sparkle; then
    fail "Sparkle.framework is embedded in the MAS bundle"
else
    pass "no Sparkle framework in the bundle"
fi

# Every Mach-O in the bundle, not just the main executable: a Debug build hides
# most of the code in a .debug.dylib and a framework would hide it in its own.
# The symbol patterns are case-sensitive by design — `grep -i _SU[A-Z]` matches
# the linker's own `..._by_suffix...` symbol and cries wolf.
MACHO=()
while IFS= read -r candidate; do
    case "$(file -b "$candidate")" in
        *Mach-O*) MACHO+=("$candidate") ;;
    esac
done < <(find "$APP/Contents" -type f)

echo "  ..  scanning ${#MACHO[@]} Mach-O file(s)"
SPARKLE_FOUND=0
for object in "${MACHO[@]}"; do
    NAME="${object#"$APP/"}"
    if otool -L "$object" 2>/dev/null | tail -n +2 | grep -qi sparkle; then
        fail "$NAME links Sparkle"; SPARKLE_FOUND=1
    fi
    if nm -a "$object" 2>/dev/null | grep -qE '([Ss]parkle|_OBJC_CLASS_\$_SP?U[A-Z])'; then
        fail "$NAME contains Sparkle symbols"; SPARKLE_FOUND=1
    fi
    if strings -a "$object" 2>/dev/null | grep -qE 'sparkle-project|SUFeedURL|SPUUpdater|SUUpdater'; then
        fail "$NAME contains Sparkle strings"; SPARKLE_FOUND=1
    fi
done
if [ "$SPARKLE_FOUND" -eq 0 ]; then
    pass "no Sparkle symbols, strings or load commands"
fi

if /usr/libexec/PlistBuddy -c 'Print :SUFeedURL' "$APP/Contents/Info.plist" >/dev/null 2>&1; then
    fail "SUFeedURL is in the MAS Info.plist"
else
    pass "no SUFeedURL in Info.plist"
fi

echo
if [ "$FAILED" -eq 0 ]; then
    echo "MAS build is clean: sandboxed, no network.client, no Sparkle."
else
    echo "MAS build is NOT shippable. See the failures above." >&2
    exit 1
fi
