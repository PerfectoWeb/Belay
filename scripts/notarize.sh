#!/usr/bin/env bash
# Submits one artefact to the Apple notary service, waits for the verdict, and
# staples the ticket. Split out of release.sh because notarization is the step
# you re-run on its own: the submission fails, you fix one entitlement, and
# rebuilding the whole archive to retry is twenty wasted minutes.
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# The profile is whatever `notarytool store-credentials` was told to call it.
# On this machine it is `gibson`, made for the sibling project and shared
# because the Apple account is the same one; nothing about it is per-app.
NOTARY_PROFILE="${BELAY_NOTARY_PROFILE:-BelayNotary}"

# Empty locally, where the profile is in the login keychain and notarytool finds
# it unaided. CI keeps it in a keychain it deletes at the end of the job, and
# notarytool only ever looks in the login keychain unless it is told otherwise.
NOTARY_KEYCHAIN="${BELAY_NOTARY_KEYCHAIN:-}"

usage() {
    cat <<'EOF'
notarize.sh - notarize and staple a .dmg, .zip or .pkg.

Usage: scripts/notarize.sh <artefact>

A .app cannot be submitted directly; zip it first, or pass the DMG that
release.sh built.

Environment:
  BELAY_NOTARY_PROFILE   notarytool keychain profile (default: BelayNotary)
  BELAY_NOTARY_KEYCHAIN  keychain holding that profile. Unset means the login
                         keychain, which is right everywhere except CI.

Exit status:
  0  notarized, stapled, and validated
  1  the notary service rejected it (the log is printed)
  2  a prerequisite or argument is missing
EOF
}

die() { echo "notarize: $*" >&2; exit 2; }

[ $# -eq 1 ] || { usage >&2; exit 2; }
case "$1" in -h|--help) usage; exit 0 ;; esac

ARTEFACT="$1"
[ -f "$ARTEFACT" ] || die "no such file: $ARTEFACT"

case "$ARTEFACT" in
    *.dmg|*.zip|*.pkg) ;;
    *) die "notarytool accepts .dmg, .zip and .pkg only; got $ARTEFACT" ;;
esac

xcrun --find notarytool >/dev/null 2>&1 || die "notarytool is missing. Xcode 13 or newer is required."
# Two ways to authenticate, in order of preference.
#
#   1. A notarytool keychain profile — set up once with store-credentials, after
#      which the .p8 never has to be read again.
#   2. The App Store Connect API key in .secrets/ — no setup, but the private key
#      is read off disk on every run.
#
# Either way this is a *release* step. Nothing about day-to-day building needs it.
PROFILE_AUTH=(--keychain-profile "$NOTARY_PROFILE")
if [ -n "$NOTARY_KEYCHAIN" ]; then
    PROFILE_AUTH+=(--keychain "$NOTARY_KEYCHAIN")
fi

AUTH=()
if xcrun notarytool history "${PROFILE_AUTH[@]}" >/dev/null 2>&1; then
    AUTH=("${PROFILE_AUTH[@]}")
elif [ -f "$ROOT/.secrets/appstoreconnect.env" ]; then
    # shellcheck disable=SC1091
    . "$ROOT/.secrets/appstoreconnect.env"
    [ -f "$ASC_KEY_PATH" ] || die "ASC_KEY_PATH points at a file that is not there: $ASC_KEY_PATH"
    AUTH=(--key "$ASC_KEY_PATH" --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER_ID")
    printf '  authenticating with the API key in .secrets/ (key id %s)\n' "$ASC_KEY_ID"
else
    die "No notarization credentials. Either run:
    xcrun notarytool store-credentials '$NOTARY_PROFILE' \\
        --key .secrets/AuthKey_<KEYID>.p8 --key-id <KEYID> --issuer <ISSUER>
  or put the key and ids in .secrets/appstoreconnect.env"
fi

echo "==> submit $(basename "$ARTEFACT")"
SUBMIT_LOG="$(mktemp -t belay-notary)"
if ! xcrun notarytool submit "$ARTEFACT" \
        "${AUTH[@]}" \
        --wait \
        --timeout 30m \
        | tee "$SUBMIT_LOG"; then
    echo "notarize: submission failed" >&2
    exit 1
fi

# notarytool exits 0 for a completed submission even when the verdict is
# Invalid, which is how unnotarized builds get shipped.
if ! grep -q 'status: Accepted' "$SUBMIT_LOG"; then
    ID="$(awk '/id:/ { print $2; exit }' "$SUBMIT_LOG")"
    echo "notarize: not accepted. Full log:" >&2
    xcrun notarytool log "$ID" "${AUTH[@]}" >&2 || true
    exit 1
fi

# ------------------------------------------------------------------- staple
# A zip cannot hold a ticket. `stapler` says so plainly — "incapable of working
# with ZIP archive files" — and the first real run of this script stopped there
# with the submission already accepted, which is the worst place to stop: the
# work is done and the artefact does not know it.
#
# So a zip is stapled by stapling what is inside it. The app beside the zip is
# the one that was submitted, and re-zipping it afterwards is what makes a
# download that Gatekeeper clears without asking the network.
STAPLE_TARGET="$ARTEFACT"
case "$ARTEFACT" in
    *.zip)
        APP="${BELAY_STAPLE_APP:-}"
        if [ -z "$APP" ]; then
            # The convention release.sh uses: dist/export/Belay.app beside
            # dist/Belay.zip.
            APP="$(dirname "$ARTEFACT")/export/$(basename "${ARTEFACT%.zip}").app"
        fi
        [ -d "$APP" ] || die "a zip cannot be stapled. Pass BELAY_STAPLE_APP=<the .app that is inside it>"
        STAPLE_TARGET="$APP"
        ;;
esac

echo "==> staple"
xcrun stapler staple "$STAPLE_TARGET"
xcrun stapler validate "$STAPLE_TARGET"

# Proves the ticket works the way Gatekeeper will read it, offline.
case "$STAPLE_TARGET" in
    *.dmg) spctl --assess --type open --context context:primary-signature -v "$STAPLE_TARGET" ;;
    *.pkg) spctl --assess --type install -v "$STAPLE_TARGET" ;;
    *.app) spctl --assess --type install -vv "$STAPLE_TARGET" ;;
esac

if [ "$STAPLE_TARGET" != "$ARTEFACT" ]; then
    echo
    echo "the ticket is stapled to $STAPLE_TARGET, not to the zip you submitted."
    echo "re-zip it before publishing:"
    echo "  ditto -c -k --sequesterRsrc --keepParent \"$STAPLE_TARGET\" <name>.zip"
fi

echo "notarized: $STAPLE_TARGET"
