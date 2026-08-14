#!/usr/bin/env bash
# Points the Homebrew cask at the release that is published now.
#
#   scripts/bump-cask.sh                 # reads the version from project.yml
#   scripts/bump-cask.sh 1.2.0
#
# The cask lives in PerfectoWeb/homebrew-tap, not in this repository, because a
# tap is a Homebrew repository and has to be laid out as one. That makes it the
# one part of a release that is easy to forget: `brew upgrade` would keep
# handing people the old disk image and nothing here would look wrong.
#
# It checks the SHA-256 against the asset GitHub is actually serving rather than
# against the local build. Those are the same file until the day they are not,
# and the one Homebrew downloads is the one that has to match.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-$(awk -F'"' '/^[[:space:]]*MARKETING_VERSION:/ { print $2; exit }' project.yml)}"
[ -n "$VERSION" ] || { echo "no version given and none in project.yml" >&2; exit 1; }

URL="https://github.com/PerfectoWeb/Belay/releases/download/v$VERSION/Belay-$VERSION.dmg"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> $VERSION"
curl -fsSL -o "$WORK/Belay.dmg" "$URL" || { echo "no published asset at $URL" >&2; exit 1; }
SHA="$(shasum -a 256 "$WORK/Belay.dmg" | awk '{print $1}')"
echo "  sha256 $SHA"

git clone --quiet https://github.com/PerfectoWeb/homebrew-tap.git "$WORK/tap"
CASK="$WORK/tap/Casks/belay.rb"
/usr/bin/sed -i '' -e "s/^  version \".*\"$/  version \"$VERSION\"/" \
                   -e "s/^  sha256 \".*\"$/  sha256 \"$SHA\"/" "$CASK"

if git -C "$WORK/tap" diff --quiet; then
    echo "  cask already points at $VERSION"
    exit 0
fi
git -C "$WORK/tap" commit -qam "Belay $VERSION"
git -C "$WORK/tap" push --quiet origin HEAD
echo "  tap updated"
