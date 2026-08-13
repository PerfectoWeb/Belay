#!/usr/bin/env bash
# Everything the CI gate runs, in the order that fails fastest.
set -euo pipefail
cd "$(dirname "$0")/.."

# The failing test's name scrolls off the top of a CI log, and the run page's
# logs need authentication to fetch, so a failure here has to name itself at the
# end where it is visible. `::error::` also becomes a GitHub annotation, which
# is readable without auth.
report_failures() {
    local log="$1"
    grep -E "recorded an issue|✘ Test|error: -\[" "$log" | head -20 | while read -r line; do
        if [ -n "${GITHUB_ACTIONS:-}" ]; then
            echo "::error::$line"
        else
            echo "FAILED: $line"
        fi
    done
}

echo "==> swift test (module suites)"
MODULE_LOG="$(mktemp)"
if ! swift test --package-path Packages/BelayKit 2>&1 | tee "$MODULE_LOG"; then
    echo
    echo "--- module suite failures ---"
    report_failures "$MODULE_LOG"
    exit 1
fi

echo "==> xcodebuild test (app target)"
xcodegen generate --quiet
APP_LOG="$(mktemp)"
if ! xcodebuild -scheme Belay -destination 'platform=macOS' \
    -derivedDataPath build/DerivedData \
    CODE_SIGN_IDENTITY="-" test 2>&1 | tee "$APP_LOG" | (xcbeautify 2>/dev/null || tail -30); then
    echo
    echo "--- app target failures ---"
    report_failures "$APP_LOG"
    exit 1
fi

# The only suite that runs inside a sandbox. Everything else — `swift test` and
# the app target's tests — runs unsandboxed, and both were green for a build in
# which the App Store app could not read ~/.claude at all.
echo "==> xcodebuild test (sandboxed App Store build)"
SANDBOX_LOG="$(mktemp)"
if ! xcodebuild -scheme Belay-MAS -destination 'platform=macOS' \
    -derivedDataPath build/DerivedData-MAS \
    CODE_SIGN_IDENTITY="-" test 2>&1 | tee "$SANDBOX_LOG" | (xcbeautify 2>/dev/null || tail -20); then
    echo
    echo "--- sandbox suite failures ---"
    report_failures "$SANDBOX_LOG"
    exit 1
fi

echo "==> string catalogue"
swift scripts/strings.swift check

echo "==> swiftlint"
swiftlint --strict

echo "==> swift-format"
swift-format lint --recursive --strict Sources Packages/BelayKit/Sources Packages/BelayKit/Tests

# Every target makes throwaway preference suites, and cfprefsd writes each one
# out as a file whether or not the test emptied the domain. Empty or not, they
# are ours and nothing will ever read them again. Swept here rather than in each
# target, so a target added later is covered without remembering to.
echo "==> scratch preferences"
swept=0
for folder in "$HOME/Library/Preferences" \
    "$HOME/Library/Containers/com.perfectoweb.belay/Data/Library/Preferences"; do
    [ -d "$folder" ] || continue
    # Matched on shape, not on a list of prefixes. Every throwaway suite ends
    # in a UUID, five different prefixes have been used over the life of the
    # tests, and the app's own domain has no UUID in it so it can never match.
    while IFS= read -r plist; do
        rm -f "$plist"
        swept=$((swept + 1))
    done < <(find "$folder" -maxdepth 1 -name '*belay*.plist' 2>/dev/null \
        | grep -Ei '\.[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}\.plist$')
done
echo "removed $swept"

echo "all green"
