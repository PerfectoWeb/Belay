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
if ! swift test --package-path Packages/VigilKit 2>&1 | tee "$MODULE_LOG"; then
    echo
    echo "--- module suite failures ---"
    report_failures "$MODULE_LOG"
    exit 1
fi

echo "==> xcodebuild test (app target)"
xcodegen generate --quiet
APP_LOG="$(mktemp)"
if ! xcodebuild -scheme Vigil -destination 'platform=macOS' \
    -derivedDataPath build/DerivedData \
    CODE_SIGN_IDENTITY="-" test 2>&1 | tee "$APP_LOG" | (xcbeautify 2>/dev/null || tail -30); then
    echo
    echo "--- app target failures ---"
    report_failures "$APP_LOG"
    exit 1
fi

echo "==> swiftlint"
swiftlint --strict

echo "==> swift-format"
swift-format lint --recursive --strict Sources Packages/VigilKit/Sources Packages/VigilKit/Tests

echo "all green"
