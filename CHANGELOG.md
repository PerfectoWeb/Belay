# Changelog

All notable changes to this project are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-08-10

First release of Vigil, a macOS menu bar app that holds the Mac awake only while
a local AI coding agent is actually working, and lets it sleep normally the rest
of the time. Detection is entirely local: no API key, no account, no telemetry.

Built and verified on macOS 26.4; the deployment target is macOS 14.0. See
`docs/QA-CHECKLIST.md` for exactly which checks have been run on a real machine
and which have not.

### Added

**Menu bar app.** `LSUIElement`, so there is no Dock icon and no window on
launch. An `NSStatusItem` with a template glyph conveys state by shape and never
by animation; left-click opens a SwiftUI panel hosted in an `NSPopover`,
right-click opens a compact menu with the mode picker and Quit. Three modes:
Auto (hold if and only if an agent is working), Always on, and Off.

**Tier A, transcript detection for Claude Code, with no configuration.**
FSEvents watches `~/.claude/projects`; a per-session cursor keeps `(inode,
offset)` and reads only the bytes appended since the last look, so an 82 MB
transcript costs the same as a fresh one. The primary signal is that the file
grew, which does not depend on the record format. On top of that, a classifier
scans the delta backwards for the last `assistant` or `user` record and reads its
`stop_reason`; metadata records are ignored, because on a real machine the
literal last line of a finished transcript is metadata far more often than not.
No growth for 45 s infers idle. Transcripts untouched for more than 10 minutes at
launch are not followed, so starting Vigil on a machine with dozens of old
sessions does not pin the Mac awake.

**Tier C, process presence.** Every 15 s, `~/.claude/sessions/<pid>.json` is
read and each pid checked with `kill(pid, 0)`. A session whose process is gone
ends immediately instead of waiting out its TTL. Only sessions Vigil is already
following are considered, and process presence never produces `.working`.

**A generic provider for everything else.** One actor hosting any number of
configured targets, each of which can watch a folder, require a named process to
be alive, or accept a routed local webhook. Any one of the three is enough.
Presets are data rather than code: Aider, Gemini CLI, Cline and Codex CLI ship as
pre-filled configurations, and adding another is one array element. Every signal
it produces is `.inferred`, webhook reports included, so an unverified local
caller can never override an exact idle from the hook bridge.

**Tier B, the hook bridge (opt-in, exact).** An `NWListener` bound to
`127.0.0.1` on an ephemeral port receives Claude Code's HTTP hooks. The port and
a 256-bit bearer token live in `~/Library/Application Support/Vigil/bridge.json`,
created `0600` inside a `0700` directory; a request without the token is answered
401 and its body is never parsed. Fourteen hook events are registered, all with
`"async": true`, so Claude Code never waits on Vigil and there is no exit code
that could disrupt a turn.

**Consent-gated hook installation.** Vigil writes to `~/.claude/settings.json`
only from a button, and shows the exact JSON it would write first. Every write
takes a timestamped backup, refuses outright if the file is not plain JSON,
and lands atomically via a same-directory temp file and `replaceItem`. Vigil's
own entries are marked by a query item in its own hook URL, so uninstall is
exact and no unrecognised key is ever added to the user's file. If the file
cannot be edited safely, the UI offers the snippet to paste by hand. The one
write with no button behind it is self-heal, which only repoints entries Vigil
already owns at a changed port.

**Power core.** At most one IOKit assertion per kind, process-wide, created with
`IOPMAssertionCreateWithProperties`, a 120 s `kIOPMAssertionTimeoutKey` and
`kIOPMAssertionTimeoutActionRelease`, and re-armed at 75% of that lifetime with
`IOPMAssertionSetProperty`. The reason string is human-readable and shows up in
`pmset -g assertions`. An optional second assertion keeps the display awake, off
by default.

**Safety rails.** A 90 s grace period after the last session goes quiet; a
10-minute session TTL; a 15-minute budget for a session that is only waiting on
the user; a 4-hour cap on one continuous hold; a battery guard that releases
below 20% on battery; and Low Power Mode shortening the grace period rather than
stopping work. The assertion is released on idle transition, quit, `SIGTERM` and
`SIGINT`, system sleep, mode change, battery guard trip and the duration cap. On
wake, the coordinator discards every timestamp it holds and re-derives from
scratch.

**Settings.** Six panes: General, Providers, Behaviour, Notifications,
Statistics and About. Every preference is typed, clamped to a documented range on
both read and write, and stamped with a schema version so a future migration is a
two-line change. A store written by a newer Vigil is ignored in favour of
defaults rather than guessed at. Open at login is registered through
`SMAppService`.

**Statistics.** How long Vigil has held the Mac awake, how much of that was while
you were away from the keyboard, and how many runs that saved. One bucket per
day, ninety days kept, sampled only while an assertion is held so an idle Vigil
schedules nothing. There are no project names and no prompts in it, only
durations and counts, and the numbers stay on the Mac unless you share a card
yourself.

**Notifications.** "An agent is waiting for you", "your agent finished" (for runs
past a 5-minute threshold by default), and a notice whenever a safety rail
releases the assertion. Each blocked session is announced once, not once per
poll. Authorization is requested the first time a notification would actually
fire, never at launch.

**Six languages.** English, Russian, German, Spanish, French and Italian, in one
String Catalog. Vigil follows the Mac's language and falls back to English;
Settings has a picker, and changing it reopens the app, because the menu bar menu
and the alerts are AppKit and will not switch language under a running process.
None of the translations have had a native review yet, which is recorded in
`BLOCKERS.md` B7 and is a wanted contribution.

**Onboarding.** One screen on first launch, dismissible, leading with what Vigil
reads and what it does not.

**Scripts.** `scripts/test.sh` (both test commands plus both linters, which is
what CI runs), `build-local.sh`, `perf-soak.sh`, `leak-check.sh`,
`verify-release.sh` and `fake-agent.sh`.

### Security

Detection is entirely local and needs no API key. Vigil reads only enough of a
transcript to tell whether it grew and what the last conversational record's
`type` and `stop_reason` were; message content is not decoded. The hook envelope
decoder has fields for `session_id`, `hook_event_name`, `cwd` and
`transcript_path` and nothing else, so the prompt text that `UserPromptSubmit`
carries is never decoded, logged or retained. Request bytes are held in the
receive closure chain rather than on the receiver actor. Session identifiers are
logged `.private`.

The one thing that touches the network is the update check, which asks GitHub
whether there is a newer release. It is off by default, it sends no query and no
identifier, and it is absent entirely from the App Store build, which ships
without the `com.apple.security.network.client` entitlement.

### Not in this release

Deliberately deferred to a later version, per `docs/09-MILESTONES.md`: per-session
opt-out, elapsed-time text in the menu bar, Shortcuts and AppleScript support, a
`vigil` command-line tool, Focus mode integration, and remote or SSH session
detection.

Claude Code is the only provider with bespoke code. Codex CLI is a preset of the
generic provider rather than a module of its own, because neither `~/.codex` nor
the `codex` binary was present on the machine this was built against and nothing
about its format could be verified. The same is true of every other preset: a
wrong path costs the user one edit and a "needs setup" badge, never a release.

The `vigil-hook` command shim that the original detection spec describes as a
fallback delivery path was cut before it was written. See
`docs/adr/003-two-tier-detection.md`.

Three things are built but not finished, and they are listed in `BLOCKERS.md`:
the app has never been notarized, so a build from someone else's Mac needs a
right-click to open; Sparkle is not wired up, so the update check finds a release
but cannot install it; and the translations have had no native review.

[1.0.0]: https://github.com/perfectoweb/vigil/releases/tag/v1.0.0
