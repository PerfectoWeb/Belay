#!/bin/bash
# Pairs the 1x and 2x exports of the disk image background into the single
# multi-representation TIFF that Finder wants.
#
#   scripts/make-dmg-background.sh art-640x420.png art-1280x840.png
#
# A plain PNG works but is drawn at 1x and looks soft on every Mac sold in the
# last decade. A TIFF holding both sizes lets Finder pick, which is how the
# installers that look sharp do it.
#
# The window is 640x420 points, set in release.sh. Both files are checked
# against that, because the failure when they do not match is not an error: the
# picture is quietly scaled, and the icons land somewhere other than where the
# art puts them.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/Promo/dmg-background.tiff"

die() { printf 'make-dmg-background: %s\n' "$1" >&2; exit 1; }

[ $# -eq 2 ] || die "usage: make-dmg-background.sh <640x420.png> <1280x840.png>"

check() {
    [ -f "$1" ] || die "$1 does not exist"
    local width height
    width="$(sips -g pixelWidth "$1" | awk '/pixelWidth/ {print $2}')"
    height="$(sips -g pixelHeight "$1" | awk '/pixelHeight/ {print $2}')"
    [ "$width" = "$2" ] && [ "$height" = "$3" ] \
        || die "$1 is ${width}x${height}, expected ${2}x${3}"
}

check "$1" 640 420
check "$2" 1280 840

mkdir -p "$ROOT/Promo"
tiffutil -cathidpicheck "$1" "$2" -out "$OUT"

echo "wrote $OUT"
echo "run scripts/release.sh; it picks the file up on its own"
