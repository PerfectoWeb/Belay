#!/usr/bin/env bash
# Submits one artefact to the Apple notary service, waits for the verdict, and
# staples the ticket. Split out of release.sh because notarization is the step
# you re-run on its own: the submission fails, you fix one entitlement, and
# rebuilding the whole archive to retry is twenty wasted minutes.
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
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

echo "==> staple"
xcrun stapler staple "$ARTEFACT"
xcrun stapler validate "$ARTEFACT"

# Proves the ticket works the way Gatekeeper will read it, offline.
case "$ARTEFACT" in
    *.dmg) spctl --assess --type open --context context:primary-signature -v "$ARTEFACT" ;;
    *.pkg) spctl --assess --type install -v "$ARTEFACT" ;;
esac

echo "notarized: $ARTEFACT"
