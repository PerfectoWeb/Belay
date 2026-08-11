#!/usr/bin/env bash
# The pre-ship gate. Runs every automated check in the order that fails fastest,
# then lists the manual checks that no script can prove.
#
# It never claims the manual items pass. A build is shippable when this exits 0
# *and* somebody has walked docs/QA-CHECKLIST.md by hand.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP="$ROOT/build/Vigil.app"
CHECKLIST="$ROOT/docs/QA-CHECKLIST.md"

SKIP_TESTS=0
SKIP_LEAKS=0
LEAK_FLAG="--address"

usage() {
    cat <<'EOF'
verify-release.sh - the pre-ship gate for Vigil.

Usage: scripts/verify-release.sh [options]

Runs, in the order that fails fastest:
  1. scripts/test.sh          build, both test suites, swiftlint, swift-format
  2. scripts/leak-check.sh    the module suites under a sanitizer
  3. build/Vigil.app          exists, is ad-hoc signed, passes codesign --verify
  3b. Vigil-MAS              sandboxed, no network.client, no Sparkle (SKIP_MAS=1 to skip)
                              --deep --strict
  4. Info.plist               LSUIElement = true, LSMinimumSystemVersion = 14.0
  5. docs/QA-CHECKLIST.md     lists every still-unchecked manual item

Options:
      --skip-tests   Skip step 1. For iterating on the later steps only.
      --skip-leaks   Skip step 2. It is the slow one; do not skip it for a real
                     release.
      --thread       Use the thread sanitizer for step 2 instead of address.
      --both         Run both sanitizers in step 2.
  -h, --help         This text.

Exit status:
  0  every automated step passed. The manual items are still unproven.
  1  an automated step failed
  2  the arguments or the environment do not make sense
EOF
}

die() { printf 'verify-release: %s\n' "$1" >&2; exit "${2:-2}"; }

while [ $# -gt 0 ]; do
    case "$1" in
        --skip-tests) SKIP_TESTS=1; shift ;;
        --skip-leaks) SKIP_LEAKS=1; shift ;;
        --thread)     LEAK_FLAG="--thread"; shift ;;
        --both)       LEAK_FLAG="--both"; shift ;;
        -h|--help)    usage; exit 0 ;;
        *) die "unknown argument '$1'. Try --help." ;;
    esac
done

STAMP="$(date '+%Y%m%d-%H%M%S')"
LOG_DIR="$ROOT/build/qa/verify-release-$STAMP"
mkdir -p "$LOG_DIR"

STEP=0
RESULTS=""
record() { RESULTS="${RESULTS}$(printf '  %-8s %s' "$1" "$2")
"; }

fail() {
    record FAIL "$1"
    printf '\n%s\n' "$RESULTS"
    printf 'verify-release: FAILED at step %s. %s\n' "$STEP" "${2:-Fix it and run again.}" >&2
    exit 1
}

banner() {
    STEP=$((STEP + 1))
    printf '\n==> step %s: %s\n' "$STEP" "$1"
}

banner "scripts/test.sh (build, tests, linters)"
if [ "$SKIP_TESTS" -eq 1 ]; then
    record SKIP "scripts/test.sh (--skip-tests)"
    echo "    skipped"
else
    if "$SCRIPT_DIR/test.sh" >"$LOG_DIR/test.log" 2>&1; then
        record PASS "scripts/test.sh"
        tail -1 "$LOG_DIR/test.log"
    else
        tail -40 "$LOG_DIR/test.log"
        fail "scripts/test.sh" "Full log: $LOG_DIR/test.log"
    fi
fi

banner "scripts/leak-check.sh $LEAK_FLAG"
if [ "$SKIP_LEAKS" -eq 1 ]; then
    record SKIP "scripts/leak-check.sh (--skip-leaks)"
    echo "    skipped"
else
    if "$SCRIPT_DIR/leak-check.sh" "$LEAK_FLAG" >"$LOG_DIR/leak-check.log" 2>&1; then
        record PASS "scripts/leak-check.sh $LEAK_FLAG"
        tail -2 "$LOG_DIR/leak-check.log"
    else
        tail -40 "$LOG_DIR/leak-check.log"
        fail "scripts/leak-check.sh" "Full log: $LOG_DIR/leak-check.log"
    fi
fi

banner "code signature of build/Vigil.app"
[ -d "$APP" ] || fail "build/Vigil.app is missing" "Build it first: scripts/build-local.sh Release"

if ! codesign --verify --deep --strict --verbose=2 "$APP" >"$LOG_DIR/codesign.log" 2>&1; then
    cat "$LOG_DIR/codesign.log"
    fail "codesign --verify --deep --strict" "Re-sign with scripts/build-local.sh Release"
fi
record PASS "codesign --verify --deep --strict"

SIGINFO="$(codesign -dvv "$APP" 2>&1 || true)"
case "$SIGINFO" in
    *"Signature=adhoc"*) record PASS "signature is ad-hoc" ;;
    *) printf '%s\n' "$SIGINFO"
       fail "signature is not ad-hoc" "docs/06 expects an ad-hoc signature for local builds." ;;
esac
printf '%s\n' "$SIGINFO" | grep -E 'Identifier=|Signature=|flags=' || true

banner "Info.plist keys"
PLIST="$APP/Contents/Info.plist"
[ -f "$PLIST" ] || fail "no Info.plist at $PLIST"

plist_value() { /usr/libexec/PlistBuddy -c "Print :$1" "$PLIST" 2>/dev/null || true; }

# LSUIElement is what keeps Vigil out of the Dock; shipping without it turns a
# menu bar utility into a regular app, which is a visible product bug.
UI_ELEMENT="$(plist_value LSUIElement)"
case "$UI_ELEMENT" in
    true|1) record PASS "LSUIElement = $UI_ELEMENT" ;;
    *) fail "LSUIElement is '${UI_ELEMENT:-missing}', expected true" "Set it in project.yml, then regenerate." ;;
esac

MIN_OS="$(plist_value LSMinimumSystemVersion)"
if [ "$MIN_OS" = "14.0" ]; then
    record PASS "LSMinimumSystemVersion = 14.0"
else
    fail "LSMinimumSystemVersion is '${MIN_OS:-missing}', expected 14.0" "docs/00-INVARIANTS.md pins the deployment target at macOS 14.0."
fi
printf '  LSUIElement=%s  LSMinimumSystemVersion=%s  CFBundleIdentifier=%s  version=%s (%s)\n' \
    "$UI_ELEMENT" "$MIN_OS" "$(plist_value CFBundleIdentifier)" \
    "$(plist_value CFBundleShortVersionString)" "$(plist_value CFBundleVersion)"

# The App Store build is a separate binary with different entitlements, so the
# checks above say nothing about it. docs/08 requires the no-Sparkle guard
# specifically; a Sparkle symbol in a MAS submission is a rejection.
banner "App Store build audit"
if [ "${SKIP_MAS:-0}" = "1" ]; then
    record "SKIP" "Vigil-MAS audit (SKIP_MAS=1)"
elif [ ! -x "$ROOT/scripts/verify-mas-build.sh" ]; then
    record FAIL "scripts/verify-mas-build.sh is missing"
elif "$ROOT/scripts/verify-mas-build.sh" >"$LOG_DIR/verify-mas.log" 2>&1; then
    record PASS "Vigil-MAS sandboxed, no network.client, no Sparkle"
else
    tail -20 "$LOG_DIR/verify-mas.log" || true
    fail "Vigil-MAS audit" "See $LOG_DIR/verify-mas.log"
fi

banner "manual checklist items still unproven"
if [ ! -f "$CHECKLIST" ]; then
    record FAIL "docs/QA-CHECKLIST.md is missing"
    fail "docs/QA-CHECKLIST.md is missing"
fi

# Print unchecked boxes under their section heading. Continuation lines of a
# multi-line item are folded in so the reminder reads as written.
UNCHECKED="$(awk '
    /^## / { section = substr($0, 4); next }
    /^[[:space:]]*- \[ \]/ {
        if (section != last_printed) { printf "\n  %s\n", section; last_printed = section }
        line = $0
        sub(/^[[:space:]]*- \[ \][[:space:]]*/, "", line)
        printf "    [ ] %s\n", line
        pending = 1
        next
    }
    /^[[:space:]]*- \[[xX!]\]/ { pending = 0; next }
    pending && /^[[:space:]]+[^[:space:]-]/ {
        line = $0
        sub(/^[[:space:]]+/, "", line)
        printf "        %s\n", line
        next
    }
    { pending = 0 }
' "$CHECKLIST")"

COUNT="$(grep -c -E '^[[:space:]]*- \[ \]' "$CHECKLIST" || true)"
if [ "$COUNT" -eq 0 ]; then
    echo "  every item in docs/QA-CHECKLIST.md is marked verified."
    record PASS "manual checklist fully marked (still a human's word, not a test)"
else
    printf '%s\n' "$UNCHECKED"
    printf '\n  %s item(s) above are NOT verified. No script can verify them.\n' "$COUNT"
    record "TODO" "$COUNT manual checklist item(s) unproven"
fi

printf '\n----------------------------------------------------------------\n'
printf 'verify-release summary\n\n%s' "$RESULTS"
printf '\nlogs: %s\n' "$LOG_DIR"
if [ "$COUNT" -gt 0 ]; then
    printf '\nAutomated checks passed. This build is NOT shippable until the %s manual\nitem(s) above have been run by hand and recorded in docs/QA-CHECKLIST.md.\n' "$COUNT"
else
    printf '\nAutomated checks passed.\n'
fi
