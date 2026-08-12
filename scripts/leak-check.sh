#!/usr/bin/env bash
# Run the BelayKit module suites under the sanitizers, once per milestone
# (docs/07, "Memory & lifecycle").
#
# Read this before trusting a clean run: on Darwin, Apple's AddressSanitizer
# ships without LeakSanitizer, so ASan here proves the absence of use-after-free,
# double-free and out-of-bounds access, not the absence of leaks. Leaks on this
# project are found by the symmetric-teardown tests and by `leaks -atExit` against
# a real run. The sanitizer that is most likely to find a real bug in a codebase
# this concurrent is the thread sanitizer: use --thread.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PACKAGE="$ROOT/Packages/BelayKit"

SANITIZERS="address"
KEEP_GOING=0
EXTRA=()

usage() {
    cat <<'EOF'
leak-check.sh - run the BelayKit test suites under the sanitizers.

Usage: scripts/leak-check.sh [options] [-- extra swift-test args]

Options:
  -a, --address     AddressSanitizer only. The default.
  -t, --thread      ThreadSanitizer only. Most likely to find a real bug here:
                    the codebase is heavily concurrent, and a data race is a
                    likelier defect than a leak.
  -b, --both        Run both, address first. They cannot share a build, so this
                    is two full sanitized builds and takes roughly twice as long.
  -k, --keep-going  Run every requested sanitizer even after one reports.
  -h, --help        This text.

Anything after `--` is passed through to `swift test`, e.g.
  scripts/leak-check.sh --thread -- --filter CoordinatorTests

Note: Apple's ASan on macOS has no LeakSanitizer, so a clean address run means
"no memory-safety error", not "no leak". The script says so in its output too.

Exit status:
  0  every requested sanitizer ran clean
  1  a sanitizer reported, or the tests failed
  2  the arguments or the environment do not make sense
EOF
}

die() { printf 'leak-check: %s\n' "$1" >&2; exit "${2:-2}"; }

while [ $# -gt 0 ]; do
    case "$1" in
        -a|--address)    SANITIZERS="address"; shift ;;
        -t|--thread)     SANITIZERS="thread"; shift ;;
        -b|--both)       SANITIZERS="address thread"; shift ;;
        -k|--keep-going) KEEP_GOING=1; shift ;;
        -h|--help)       usage; exit 0 ;;
        --)              shift; EXTRA=("$@"); break ;;
        *) die "unknown argument '$1'. Try --help." ;;
    esac
done

command -v swift >/dev/null 2>&1 || die "swift not found; install the Xcode command line tools"
[ -f "$PACKAGE/Package.swift" ] || die "no package at $PACKAGE"

STAMP="$(date '+%Y%m%d-%H%M%S')"
LOG_DIR="$ROOT/build/qa/leak-check-$STAMP"
mkdir -p "$LOG_DIR"

# Sanitized builds must not share a build directory with the ordinary one, or
# swift test rebuilds the world every time you alternate between them.
run_one() {
    local san="$1"
    local log="$LOG_DIR/$san.log"
    local status=0

    echo "==> swift test --sanitize=$san"
    # TSan needs a bigger history buffer to report the second stack of a race,
    # and halt_on_error=0 so one report does not hide the rest.
    TSAN_OPTIONS="history_size=7 halt_on_error=0 ${TSAN_OPTIONS:-}" \
    ASAN_OPTIONS="detect_stack_use_after_return=1 halt_on_error=0 ${ASAN_OPTIONS:-}" \
    swift test \
        --package-path "$PACKAGE" \
        --scratch-path "$ROOT/build/qa/.build-$san" \
        --sanitize="$san" \
        ${EXTRA+"${EXTRA[@]}"} 2>&1 | tee "$log" || status=$?

    local reports
    reports="$(grep -c -E 'ERROR: (Address|Leak)Sanitizer|WARNING: ThreadSanitizer|runtime error:' "$log" || true)"

    echo
    echo "--- $san summary ---"
    if [ "$reports" -gt 0 ]; then
        echo "$reports sanitizer report(s). First occurrences, with the frames that name our code:"
        grep -n -E 'ERROR: (Address|Leak)Sanitizer|WARNING: ThreadSanitizer|runtime error:|SUMMARY: .*Sanitizer' "$log" | head -40
        echo
        echo "Full log: $log"
        return 1
    fi

    if [ "$status" -ne 0 ]; then
        echo "no sanitizer report, but the test run exited $status. Failing tests:"
        grep -E '^.*: error:|failed \(|Test Case .* failed|✘' "$log" | head -30
        echo
        echo "Full log: $log"
        return 1
    fi

    local passed
    passed="$(grep -c -E 'Test Case .* passed|✔' "$log" || true)"
    echo "clean under $san ($passed test results, no reports)."
    [ "$san" != "address" ] || echo "Reminder: Darwin ASan has no leak detector. This says no memory-safety error, not no leak."
    return 0
}

FAILED=0
for san in $SANITIZERS; do
    if ! run_one "$san"; then
        FAILED=1
        [ "$KEEP_GOING" -eq 1 ] || break
    fi
    echo
done

echo "logs: $LOG_DIR"
if [ "$FAILED" -eq 1 ]; then
    echo "leak-check: sanitizer findings above. Report them to whoever owns the module; do not paper over them." >&2
    exit 1
fi
echo "leak-check: clean."
