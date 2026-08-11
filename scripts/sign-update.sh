#!/usr/bin/env bash
# Signs a release for Sparkle and regenerates the appcast.
#
# WRITTEN, NEVER RUN. Sparkle is not wired into the build yet and there is no
# EdDSA key pair (BLOCKERS.md B3).
#
# The private key lives in the login Keychain and nowhere else. generate_appcast
# looks it up itself — it is never passed on the command line, never written to
# a file, and never read by this script, so it cannot end up in the repo, in
# shell history, or in a CI log. Create it once with Sparkle's `generate_keys`,
# back up the printed private key somewhere offline, and delete the backup file.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# PLACEHOLDER — BLOCKERS.md B3. Must match Appcast.feedURL in
# Packages/VigilKit/Sources/VigilTipJar/UpdateChannel.swift and SUFeedURL in the
# direct build's Info.plist. HTTPS only: an appcast over HTTP hands an attacker
# the update stream.
DOWNLOAD_PREFIX="${VIGIL_DOWNLOAD_PREFIX:-https://updates.invalid.example/vigil/}"

RELEASES="${VIGIL_RELEASES_DIR:-$ROOT/dist/releases}"

usage() {
    cat <<'EOF'
sign-update.sh - EdDSA-sign the releases in a directory and rebuild appcast.xml.

Usage: scripts/sign-update.sh [releases-dir]

The directory holds every published .dmg (or .zip). generate_appcast signs each
one, reads the version out of the bundle inside, and writes appcast.xml next to
them. Keep old releases in place: dropping one removes it from the appcast and
breaks delta updates for anyone still on it.

Environment:
  VIGIL_DOWNLOAD_PREFIX  URL the DMGs are served from. Required; the placeholder
                         is rejected.
  VIGIL_RELEASES_DIR     default: dist/releases
  SPARKLE_BIN            directory holding generate_appcast, if it is not on
                         PATH (the Sparkle distribution's bin/).

Exit status:
  0  appcast.xml regenerated
  2  a prerequisite is missing; nothing was written
EOF
}

die() { echo "sign-update: $*" >&2; exit 2; }

case "${1:-}" in
    -h|--help) usage; exit 0 ;;
    "") ;;
    *) RELEASES="$1" ;;
esac

case "$DOWNLOAD_PREFIX" in
    *invalid.example*) die "VIGIL_DOWNLOAD_PREFIX is still the placeholder. See BLOCKERS.md B3." ;;
    https://*) ;;
    *) die "the download prefix must be https://" ;;
esac

if [ -n "${SPARKLE_BIN:-}" ]; then
    GENERATE_APPCAST="$SPARKLE_BIN/generate_appcast"
else
    GENERATE_APPCAST="$(command -v generate_appcast || true)"
fi
[ -n "$GENERATE_APPCAST" ] && [ -x "$GENERATE_APPCAST" ] \
    || die "generate_appcast not found. Download the Sparkle 2 distribution and set SPARKLE_BIN to its bin/ directory."

[ -d "$RELEASES" ] || die "no releases directory at $RELEASES"
ls "$RELEASES"/*.dmg "$RELEASES"/*.zip >/dev/null 2>&1 || die "$RELEASES contains no .dmg or .zip to sign"

# generate_appcast reads the key from the Keychain under this service name. A
# clear failure here beats an appcast full of unsigned entries, which Sparkle
# clients silently refuse.
security find-generic-password -s 'https://sparkle-project.org' >/dev/null 2>&1 \
    || die "no Sparkle EdDSA private key in the login Keychain. Run Sparkle's generate_keys once, on the release machine only."

echo "==> generate_appcast $RELEASES"
"$GENERATE_APPCAST" \
    --download-url-prefix "$DOWNLOAD_PREFIX" \
    --maximum-versions 5 \
    "$RELEASES"

APPCAST="$RELEASES/appcast.xml"
[ -f "$APPCAST" ] || die "generate_appcast exited 0 but wrote no appcast.xml"

grep -q 'sparkle:edSignature' "$APPCAST" || die "$APPCAST has no EdDSA signatures; clients would reject every update"

echo
echo "appcast: $APPCAST"
echo "publish: upload it and the .dmg files to $DOWNLOAD_PREFIX"
