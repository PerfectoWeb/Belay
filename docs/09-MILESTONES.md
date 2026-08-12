# 09 — Milestones

Each milestone ends with: green build, green tests, lint clean, `PROJECT_STATE.md`
updated. Ship-ability increases monotonically — from M1 onward there is always a
working app.

---

## M0 — Discovery & scaffold

- Preflight toolchain checks; install `xcodegen`, `swiftlint`, `swift-format`
- **Empirical discovery** of `~/.claude` layout, transcript format, hook schema,
  and `~/.codex` if present → `docs/DISCOVERY.md`
- `project.yml`, package skeletons, `.swiftlint.yml`, `.swift-format`,
  `.gitignore`, `scripts/build-local.sh`
- App launches, shows a placeholder status item, quits cleanly

**Exit:** `scripts/build-local.sh` produces a runnable app.

---

## M1 — Power core (first genuinely useful build)

- `BelayPower`: `PowerAssertionController`, backend protocol + mock, timeout
  refresh loop, battery/AC monitoring, sleep/wake notifications, signal handlers
- `BelaySettings`: typed preferences store with defaults and a migration hook
- Status item with Off / Always-on modes and working icon states
- Full unit tests for the assertion controller including balance property tests

**Exit:** Belay works as a better `caffeinate` with a UI. Verified via
`pmset -g assertions`. This alone would be a shippable free utility.

---

## M2 — Claude Code detection, Tier A

- `BelayCore`: `ActivitySignal`, `SignalBus`, `ActivityCoordinator` state machine,
  `Clock`, TTL eviction, grace period, mode/policy application
- `BelayProviders`: `ClaudeCodeProvider` with the FSEvents transcript watcher,
  incremental cursors, and the process-presence safety net
- Folder-access flow (`NSOpenPanel` + security-scoped bookmark) behind
  `FileAccessProvider`
- `scripts/fake-agent.sh` + integration tests
- Panel shows live sessions

**Exit:** Auto mode works end-to-end against a real Claude Code session with
zero configuration.

---

## M3 — Hook bridge, Tier B

- `BelayHookBridge`: receiver (HTTP loopback if supported, Unix socket + shim
  otherwise), token auth, fire-and-forget semantics
- `BelayHelperCLI` target if the shim is needed
- Safe `settings.json` installer: backup, atomic merge, marked entries, diff
  preview UI, clean uninstall, self-heal on bundle move
- Confidence fusion in the coordinator (`.exact` beats `.inferred`)
- `awaitingUser` state driven by the `Notification` event

**Exit:** Sub-second, exact detection; hooks install and uninstall cleanly;
Claude Code is provably unaffected (measure turn latency with and without).

---

## M4 — Product polish

- Settings window, all panes
- Onboarding screen with the privacy statement
- Notifications (needs-input, task-finished, safety-release) with actions
- Launch at login via `SMAppService`
- Localisation scaffolding (`.xcstrings`), full accessibility pass
- ~~Demo mode~~ — built, then removed. It was reachable by accident from the
  menu and injected fake sessions into a real user's panel. See PROJECT_STATE D16.

**Exit:** A stranger can install it and understand it without documentation.

---

## M5 — Additional providers

- `CodexProvider` (verify empirically first; skip and document if the surface
  isn't there)
- `GenericProvider`: folder watch / process watch / local webhook, with preset
  templates
- Provider settings UI generated from descriptors, not hand-written

**Exit:** A new provider can be added in one file; README documents the webhook
one-liner for arbitrary tools.

---

## M6 — Distribution

- Two schemes (`Belay`, `Belay-MAS`), entitlements, compile flags
- Sparkle 2 integration + appcast template + `scripts/sign-update.sh`
- `BelayTipJar` with both implementations behind one protocol
- `scripts/release.sh` and `scripts/notarize.sh` (written, not run)
- CI workflow file, including the "no Sparkle in MAS" guard

**Exit:** Both schemes build; the MAS build contains no Sparkle and no
`network.client`.

---

## M7 — Hardening & release prep

- Performance soak against the budgets in `docs/08`; fix anything over
- ASan + leak run; zero leaks
- Manual QA checklist executed on every supported macOS version
- ADRs written; module READMEs written; docs updated to match reality
- `README.md`, `CHANGELOG.md`, `LICENSE`, `CONTRIBUTING.md`, `SECURITY.md`
- `PROJECT_STATE.md`: final status, deferred items, v1.1 candidates, and exactly
  what needs an Apple Developer account

**Exit:** Production-ready v1.0.

---

## Deliberately deferred to v1.1+

Per-session opt-out · menu bar elapsed-time text · session history and stats ·
Shortcuts/AppleScript support · `belay` CLI · Focus mode integration ·
Russian localisation · remote/SSH session detection.

Note them in `PROJECT_STATE.md` rather than building them. Scope discipline is
part of the deliverable.
