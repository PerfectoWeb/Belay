#!/usr/bin/env bash
# Everything the CI gate runs, in the order that fails fastest.
set -euo pipefail
cd "$(dirname "$0")/.."

echo "==> swift test (module suites)"
swift test --package-path Packages/VigilKit

echo "==> xcodebuild test (app target)"
xcodegen generate --quiet
xcodebuild -scheme Vigil -destination 'platform=macOS' \
    -derivedDataPath build/DerivedData \
    CODE_SIGN_IDENTITY="-" test | (xcbeautify 2>/dev/null || tail -30)

echo "==> swiftlint"
swiftlint --strict

echo "==> swift-format"
swift-format lint --recursive --strict Sources Packages/VigilKit/Sources Packages/VigilKit/Tests

echo "all green"
