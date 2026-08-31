# 08 – Testing & performance

## Budgets (these are pass/fail, not aspirations)

| Metric | Budget | How to measure |
|---|---|---|
| Idle CPU (armed, no sessions) | < 0.1% avg over 30 min | `scripts/perf-soak.sh` sampling `ps -o %cpu` |
| Active CPU (one busy session) | < 1.0% avg | same, during a real Claude Code run |
| RSS after 8 h | < 40 MB, and **flat** vs the 30-min mark | `footprint` / Instruments Allocations |
| Wakeups per second (idle) | < 3 | `powermetrics --samplers tasks` |
| Cold launch to menu bar icon | < 300 ms | signpost from `applicationDidFinishLaunching` |
| Hook handler round trip | < 50 ms p99 | instrumented in the shim |

If a budget is missed, fix the design – do not relax the number. The whole
premise of the product is "a power tool that doesn't cost power".

Common causes if you blow the CPU budget: a repeating `Timer` at 1 Hz, SwiftUI
re-rendering the panel while it's closed (it shouldn't exist when closed),
re-reading transcript files from offset 0, or FSEvents configured with latency 0.

## Test layers

**1. Unit – the state machine (the important ones).**
`ActivityCoordinator` with an injected `TestClock`. Cover:
- single session working → idle → grace → release
- two sessions, one idle, one working → still held
- a session that goes silent forever → evicted at TTL, released
- exact `.idle` beating a late `.inferred` `.working` for the same session
- rapid flapping (working/idle 50 times in 10 s) → exactly one hold, one release
- max duration cap fires mid-work → release + user-visible reason
- battery guard trips and recovers
- mode changes at every point in the state graph

Property-style test: generate thousands of random signal sequences, assert the
invariant "assertion held ⟺ (mode == always) ∨ (some session working/awaiting
within grace)" and that create/release calls on the mock backend are always
balanced.

**2. Unit – transcript parsing.**
Fixture files in `Tests/Fixtures/`: a normal session, a truncated write, a
partial trailing line, an unknown record type, a 5 MB session, a file with
CRLF, an empty file. Assert the cursor never re-reads and never crashes.

**3. Integration – the fake agent.**
`scripts/fake-agent.sh` writes JSONL at a configurable cadence and can simulate:
steady work, a 3-minute tool call with no output, an abrupt death, truncation,
and two concurrent sessions. Wire it into a test target that runs the whole
pipeline (provider → bus → coordinator → mock power backend) and asserts on the
resulting hold/release timeline.

**4. Manual E2E – required before calling v1.0 done.**
Documented as a checklist in `docs/QA-CHECKLIST.md`, run on the host machine:
- start a real long Claude Code task; confirm via `pmset -g assertions` that the
  assertion appears within ~5 s and persists through the whole run
- confirm it **disappears** within grace + 10 s of completion
- set system sleep to 1 minute, run a 10-minute task, confirm no sleep, then
  confirm the Mac sleeps ~1 minute after the task ends
- kill `claude` mid-task with `SIGKILL`; confirm release within TTL
- force-quit Belay while holding; confirm the assertion self-releases within
  the timeout window
- sleep the Mac manually, wake it, confirm state resyncs correctly
- run on macOS 14, 15 and 26 (VMs are fine for 14/15), and on the 27 beta
- verify light mode, dark mode, tinted menu bar, Reduce Transparency,
  and a second display with different scaling

## CI

`.github/workflows/ci.yml` – build, test, SwiftLint `--strict`, swift-format
lint, and a step that greps the MAS build for Sparkle symbols and fails if
found. Write the file; do not run or commit it.

## Instrumentation

Add `OSSignposter` intervals around: transcript delta parse, hook receive,
coordinator decision, assertion create/release. This turns a vague "it feels
laggy" into a five-second Instruments answer, and costs nothing when not tracing.
