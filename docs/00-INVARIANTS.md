# 00 — Invariants and ground rules

Vigil is a macOS menu bar app that holds the Mac awake only while a local AI
coding agent is actively working. This file is the short version of the rules
the rest of `docs/` explains at length. If you only read one file before
touching the code, read this one.

## Build & test

```bash
scripts/test.sh                                      # everything CI runs, fails fastest first
swift test --package-path Packages/VigilKit          # the module suites (nearly all tests)
xcodegen generate                                    # regenerate Vigil.xcodeproj from project.yml
xcodebuild -scheme Vigil -destination 'platform=macOS' build
xcodebuild -scheme Vigil -destination 'platform=macOS' test   # app target only, see below
swiftlint --strict
swift-format lint --recursive Sources Packages/VigilKit/Sources Packages/VigilKit/Tests
scripts/build-local.sh                               # ad-hoc signed .app in build/
```

Tests live in two places and that is deliberate: an XcodeGen scheme cannot
reference a local SwiftPM package's test targets, so `xcodebuild test` runs only
`VigilAppTests` and the module suites run under `swift test`. `scripts/test.sh`
runs both plus both linters. See `PROJECT_STATE.md` D2.

Never hand-edit `Vigil.xcodeproj`. It is generated. Edit `project.yml`.

## Non-negotiables

- No AI provider API keys, ever. Detection is local-only.
- No `caffeinate`, no `NSProcessInfo.beginActivity` as the primary mechanism.
  Use IOKit `IOPMAssertionCreateWithProperties` with a self-releasing timeout.
- Deployment target: macOS 14.0. Must build and run clean on 14 / 15 / 26.
- Idle CPU < 0.1%, idle RSS < 40 MB, no polling faster than 5 s.
- Swift 6 language mode, strict concurrency, no `@unchecked Sendable` without a
  written justification in the file header.

## Architecture in one breath

Providers emit `ActivitySignal`s → `SignalBus` → `ActivityCoordinator` (a
deterministic state machine with an injected clock) → `PowerAssertionController`
holds or releases exactly one IOKit assertion. UI observes the coordinator and
never touches IOKit directly.

## Invariants (violating any of these is a bug, not a preference)

1. At most **one** power assertion exists at any time, process-wide.
2. Every assertion carries a hard timeout and is refreshed while busy, so a
   crashed or wedged app cannot pin the Mac awake.
3. Every session tracked has a TTL; a session with no signal for `sessionTTL`
   is treated as dead regardless of what the last signal said.
4. The assertion is released on: idle transition, app termination, SIGTERM/SIGINT,
   user toggle off, battery guard trip, and max-duration cap.
5. A hook handler must never block or slow down Claude Code. Fire-and-forget,
   sub-50 ms, always exit 0.
6. Vigil never writes to `~/.claude/` without explicit, per-action user consent
   in the UI, and always makes a timestamped backup first.

## Style

See `docs/07-ENGINEERING-STANDARDS.md`. Short answer: write it like a senior
macOS engineer who dislikes ceremony. Comments explain *why*, never *what*.

## State

`PROJECT_STATE.md` is the source of truth for progress. Update it every milestone.
