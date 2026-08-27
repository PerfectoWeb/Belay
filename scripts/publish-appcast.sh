#!/usr/bin/env bash
# Builds the Sparkle appcast from the published releases and puts it on the site.
#
#   scripts/publish-appcast.sh            # build it, show it, publish nothing
#   scripts/publish-appcast.sh --publish  # and push it to gh-pages
#
# Four steps, and only the second one needs a human:
#
#   1. download every published .dmg from GitHub releases
#   2. sign them and write appcast.xml   <-- macOS asks for the Keychain here
#   3. point each enclosure at its own release tag
#   4. commit appcast.xml to gh-pages, beside index.html
#
# **The Keychain prompt.** The EdDSA private key lives in the login Keychain and
# `generate_appcast` reads it directly, so the first run puts a dialog on screen
# asking whether it may. Answer "Always Allow" and no later run will ask again.
# There is no way around this and there should not be: a key a script can read
# unattended is a key a script can leak.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT"

RELEASES="$ROOT/dist/releases"
PUBLISH=0
[ "${1:-}" = "--publish" ] && PUBLISH=1

die() { echo "publish-appcast: $*" >&2; exit 2; }

# ---------------------------------------------------------------- 1. the DMGs
#
# Every published version, not just the newest. Sparkle offers somebody two
# releases behind a direct path forward only if the appcast still names the
# version they are on, and `generate_appcast` reads versions out of the bundles
# rather than from anything we tell it.
echo "==> collect the published releases"
command -v gh >/dev/null || die "gh is not installed"
mkdir -p "$RELEASES"
tags="$(gh release list -R PerfectoWeb/Belay --limit 20 --json tagName --jq '.[].tagName')" \
    || die "could not list the releases; is gh signed in?"
[ -n "$tags" ] || die "the repository has no published releases"

for tag in $tags; do
    # The versioned name only. Each release also carries a copy under the stable
    # name Belay.dmg for the README's download button, and two files of the same
    # version make generate_appcast write the version twice.
    #
    # A failure here used to be swallowed. It cannot be: this directory keeps
    # older releases on purpose, so a download that fails leaves the previous
    # run's files in place, every check downstream passes, and the appcast that
    # gets published quietly omits the version somebody is waiting for.
    #
    # Retried, because one flaky download should not throw away twenty good
    # ones. GitHub hands out a TLS timeout often enough that a single attempt
    # turned a release into a coin toss.
    attempt=1
    until gh release download "$tag" -R PerfectoWeb/Belay -D "$RELEASES" \
        --pattern "Belay-*.dmg" --clobber >/dev/null 2>&1; do
        [ "$attempt" -ge 4 ] && die "could not download the assets of $tag"
        sleep $((attempt * 3))
        attempt=$((attempt + 1))
    done

    want="$RELEASES/Belay-${tag#v}.dmg"
    [ -f "$want" ] || die "$tag published no Belay-${tag#v}.dmg"
done
rm -f "$RELEASES/Belay.dmg"

# Drop any release whose app has no SUPublicEDKey. Sparkle refuses to offer one
# of those to a build that has a key, and says why: "Sparkle only supports
# rotation, but not removal of (Ed)DSA keys." v1.0.0 and v1.1.0 shipped before
# the key existed, so generate_appcast writes them unsigned and the signature
# gate then refuses the whole appcast. Without this the first real publish would
# be blocked by two releases nobody can update from anyway.
for dmg in "$RELEASES"/*.dmg; do
    [ -f "$dmg" ] || continue
    mount="$(mktemp -d)"
    hdiutil attach -nobrowse -quiet -mountpoint "$mount" "$dmg" || continue
    key="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' \
        "$mount/Belay.app/Contents/Info.plist" 2>/dev/null || true)"
    hdiutil detach -quiet "$mount" || true
    rmdir "$mount" 2>/dev/null || true
    if [ -z "$key" ]; then
        echo "  skipping $(basename "$dmg"): no SUPublicEDKey, so it cannot be updated from"
        rm -f "$dmg"
    fi
done

ls "$RELEASES"/*.dmg >/dev/null 2>&1 \
    || die "no release carries a signing key yet; there is nothing to publish"
ls -1 "$RELEASES"/*.dmg | sed 's|.*/|  |'

# Release notes, for the update dialog. generate_appcast embeds any
# Belay-<version>.html sitting beside the matching DMG as that item's
# description; without one the dialog shows an empty pane, which is what 1.2.1
# shipped with. The notes live in the repository so they are written with the
# release, not remembered at publish time.
if ls "$ROOT/docs/release-notes"/Belay-*.html >/dev/null 2>&1; then
    cp "$ROOT/docs/release-notes"/Belay-*.html "$RELEASES/"
    echo "  with notes: $(ls "$ROOT/docs/release-notes"/Belay-*.html | sed 's|.*/||' | tr '\n' ' ')"
fi

# ------------------------------------------------- 2 and 3. sign, and retag
#
# generate_appcast ships inside the Sparkle package rather than on PATH, so it
# is found where SwiftPM put it unless SPARKLE_BIN says otherwise.
if [ -z "${SPARKLE_BIN:-}" ]; then
    found="$(find "$HOME/Library/Developer/Xcode/DerivedData" \
        -path '*sparkle/Sparkle/bin/generate_appcast' -type f 2>/dev/null | head -1)"
    [ -n "$found" ] || die "generate_appcast not found; set SPARKLE_BIN to Sparkle's bin/"
    SPARKLE_BIN="$(dirname "$found")"
fi
export SPARKLE_BIN

echo
echo "==> sign and build the appcast"
echo "    macOS will ask for the Keychain. Answer Always Allow."
"$SCRIPT_DIR/sign-update.sh" "$RELEASES"

APPCAST="$RELEASES/appcast.xml"
[ -f "$APPCAST" ] || die "no appcast was written"

echo
echo "==> what it says"
{ grep -oE '<title>[^<]*</title>|sparkle:version="[^"]*"|url="[^"]*"' "$APPCAST" || true; } \
    | sed 's/^/  /'

if [ "$PUBLISH" = 0 ]; then
    echo
    echo "not published. Re-run with --publish to put it on the site."
    exit 0
fi

# ----------------------------------------------------------------- 4. publish
#
# A worktree rather than a branch switch: the working tree stays where it is,
# which matters because this script is run from a repository somebody is in the
# middle of using.
echo
echo "==> publish to gh-pages"
WORKTREE="$(mktemp -d)"
trap 'git worktree remove --force "$WORKTREE" >/dev/null 2>&1 || true' EXIT
git fetch --quiet origin gh-pages
git worktree add --quiet --detach "$WORKTREE" origin/gh-pages
cp "$APPCAST" "$WORKTREE/appcast.xml"
git -C "$WORKTREE" add appcast.xml
if git -C "$WORKTREE" diff --cached --quiet; then
    echo "  appcast.xml is already what is published; nothing to do"
    exit 0
fi
git -C "$WORKTREE" commit --quiet -m "Publish the appcast"
git -C "$WORKTREE" push --quiet origin HEAD:gh-pages
echo "  https://perfectoweb.github.io/Belay/appcast.xml"
