#!/usr/bin/env bash
# Signs a release for Sparkle and regenerates the appcast.
#
# Called by publish-appcast.sh, which is the entry point worth using: it fetches
# the releases first and puts the result on the site afterwards. This half is the
# signing, and it is separate because signing is the step that needs the key.
#
# The private key lives in the login Keychain and nowhere else. generate_appcast
# looks it up itself — it is never passed on the command line, never written to
# a file, and never read by this script, so it cannot end up in the repo, in
# shell history, or in a CI log. Create it once with Sparkle's `generate_keys`,
# back up the printed private key somewhere offline, and delete the backup file.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Where the disk images are served from. GitHub's release assets, which is where
# they already are, so nothing has to be uploaded twice.
#
# generate_appcast builds each enclosure URL as this prefix plus the file name,
# and GitHub's are not laid out that way: every release sits under its own tag.
# The prefix below is therefore a stand-in, and `retag` below rewrites each URL
# to the tag its version belongs to. Doing it afterwards rather than trying to
# make one prefix fit means the appcast can name several versions at once, which
# is what Sparkle needs to offer somebody two releases behind a direct path
# forward.
DOWNLOAD_PREFIX="${BELAY_DOWNLOAD_PREFIX:-https://github.com/PerfectoWeb/Belay/releases/download/}"

RELEASES="${BELAY_RELEASES_DIR:-$ROOT/dist/releases}"

usage() {
    cat <<'EOF'
sign-update.sh - EdDSA-sign the releases in a directory and rebuild appcast.xml.

Usage: scripts/sign-update.sh [releases-dir]

The directory holds every published .dmg (or .zip). generate_appcast signs each
one, reads the version out of the bundle inside, and writes appcast.xml next to
them. Keep old releases in place: dropping one removes it from the appcast and
breaks delta updates for anyone still on it.

Environment:
  BELAY_DOWNLOAD_PREFIX  URL the DMGs are served from. Required; the placeholder
                         is rejected.
  BELAY_RELEASES_DIR     default: dist/releases
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
    *invalid.example*) die "BELAY_DOWNLOAD_PREFIX is still the placeholder. See BLOCKERS.md B3." ;;
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
# One `ls` over both globs fails whenever either one matches nothing, which is
# every ordinary run: this project ships disk images and no zips. The first run
# of this script died on exactly that, saying the directory was empty while
# holding two disk images.
have_any=0
for candidate in "$RELEASES"/*.dmg "$RELEASES"/*.zip; do
    [ -f "$candidate" ] && have_any=1
done
[ "$have_any" = 1 ] || die "$RELEASES contains no .dmg or .zip to sign"

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

# --- put each enclosure under its own tag -------------------------------------
#
# generate_appcast writes prefix + filename, and GitHub serves a release asset
# from a path that carries its tag: .../releases/download/v1.2.0/Belay-1.2.0.dmg.
# The version is already in the file name, so the tag is recovered from it
# rather than guessed. A URL that does not match that shape is left alone and
# reported, because rewriting it into a guess would produce an appcast full of
# links that 404 at the moment somebody tries to update.
echo "==> point each enclosure at its own tag"
python3 "$SCRIPT_DIR/retag-appcast.py" "$APPCAST" "$DOWNLOAD_PREFIX" \
    || die "could not rewrite the enclosure URLs"

echo
echo "appcast: $APPCAST"
echo "publish: commit it to the gh-pages branch as appcast.xml, beside index.html"
