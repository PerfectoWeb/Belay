#!/bin/bash
# Builds Promo/dmg/VolumeIcon.icns from Promo/dmg/belay-volumeIcon.png.
#
#   scripts/make-volume-icon.sh
#
# The source has to be 1024x1024. Every size in the icns is resampled from it,
# including the 16pt one Finder puts in the sidebar, so the source wants to be
# the artwork rather than an export of a smaller version.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE="$ROOT/Promo/dmg/belay-volumeIcon.png"
OUT="$ROOT/Promo/dmg/VolumeIcon.icns"

die() { printf 'make-volume-icon: %s\n' "$1" >&2; exit 1; }

[ -f "$SOURCE" ] || die "$SOURCE does not exist"

WIDTH="$(sips -g pixelWidth "$SOURCE" | awk '/pixelWidth/ {print $2}')"
HEIGHT="$(sips -g pixelHeight "$SOURCE" | awk '/pixelHeight/ {print $2}')"
[ "$WIDTH" = "1024" ] && [ "$HEIGHT" = "1024" ] \
    || die "$SOURCE is ${WIDTH}x${HEIGHT}, expected 1024x1024"

ICONSET="$(mktemp -d)/VolumeIcon.iconset"
mkdir -p "$ICONSET"
trap 'rm -rf "$(dirname "$ICONSET")"' EXIT

# Apple's ten entries. The @2x names are the same pixel sizes as the next entry
# up, and both have to be present or Finder falls back unpredictably.
for spec in "16 16x16" "32 16x16@2x" "32 32x32" "64 32x32@2x" \
            "128 128x128" "256 128x128@2x" "256 256x256" "512 256x256@2x" \
            "512 512x512" "1024 512x512@2x"; do
    set -- $spec
    sips -Z "$1" "$SOURCE" --out "$ICONSET/icon_$2.png" >/dev/null
done

iconutil -c icns "$ICONSET" -o "$OUT"
echo "wrote $OUT"
